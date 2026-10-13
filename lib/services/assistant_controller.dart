import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/assistant_status.dart';
import '../models/chat_message.dart';
import '../models/tool_result.dart';
import '../services/local_router.dart';
import '../services/memory_service.dart';
import '../services/settings_service.dart';
import '../services/tool_registry.dart';
import '../services/tts_service.dart';
import '../services/voice_service.dart';
import 'ai/ai_config.dart';
import 'ai/ai_service.dart';
import 'ai/api_key_store.dart';
import 'ai/jarvis_agent.dart';
import 'ai/jarvis_persona.dart';

/// App ka brain: mic/text -> router -> tool registry -> (TTS) -> history.
///
/// Phase 4 me yahan ek online [AiService] jud jayega; tab tak jo bhi jawab
/// dikhta hai wo ya to device-tool ka real result hai ya ek honest "ye abhi
/// support nahi" line. Koi scripted/fake AI answer nahi.
class AssistantController extends ChangeNotifier {
  AssistantController({
    required this.settingsService,
    required this.memory,
    required this.registry,
    required TtsService tts,
    required VoiceService voice,
    this.router = const LocalRouter(),
    JarvisApiKeyStore? keyStore,
  })  : _tts = tts,
        _voice = voice,
        _keys = keyStore ?? JarvisApiKeyStore();

  final SettingsService settingsService;
  final MemoryService memory;
  final ToolRegistry registry;
  final LocalRouter router;
  final TtsService _tts;
  final VoiceService _voice;
  final JarvisApiKeyStore _keys;

  /// AI layer: service हर turn पर नई बनती है (Settings बदलते ही लागू), और
  /// [JarvisAgent] सिर्फ ToolRegistry के ज़रिए ही कुछ चलाता है।
  late final JarvisAgent agent = JarvisAgent(
    registry: registry,
    serviceBuilder: buildAiService,
  );

  static const Duration duplicateWindow = Duration(seconds: 4);

  JarvisSettings settings = const JarvisSettings();
  AssistantStatus status = AssistantStatus.idle;
  String statusDetail = '';
  List<ChatMessage> messages = <ChatMessage>[];
  String partialHeard = '';
  double micLevel = 0;
  List<ToolResult> lastToolResults = <ToolResult>[];
  String? lastSpokenText;
  bool voiceAvailable = false;

  /// null = platform ne bataya hi nahi; false = us language ka TTS voice
  /// इंस्टॉल नहीं (UI laal chip dikhata hai).
  bool? ttsLanguageOk;
  bool busy = false;

  /// AI key sirf RAM me cache hotी hai (boot + save par secure storage se padhi
  /// जाती hai) — SharedPreferences/UI/logs me कभी नहीं।
  String? _aiKey;

  /// Chat me AI के असली tool results दिखाने के लिए (Phase 5/6 ke actions)।
  List<ToolResult> lastAiToolResults = <ToolResult>[];
  AiErrorKind? lastAiError;
  AiHealth? lastAiTest;
  bool testingAi = false;

  String? _lastUserText;
  DateTime? _lastUserAt;
  String? _repeatTarget;

  /// UI boot hone par ek baar.
  Future<void> boot() async {
    settings = await settingsService.load();
    // AI key (agar provider chalu है) — sirf is turn ke liye RAM me cache।
    await _reloadAiKey();
    memory.enabled = settings.rememberHistory;
    messages = await memory.loadHistory();
    _safeNotify();
    await _tts.configure(
      language: settings.ttsLanguage,
      rate: settings.ttsRate,
      pitch: settings.ttsPitch,
    );
    ttsLanguageOk = await _tts.languageInstalled(settings.ttsLanguage);
    voiceAvailable = await _voice.initialize();
    statusDetail = voiceAvailable
        ? 'माइक तैयार है'
        : 'माइक उपलब्ध नहीं — टाइप करके भी चल जाएगा';
    _safeNotify();
  }

  // ------------------------------------------------------------------ mic

  Future<void> startListening() async {
    if (busy) return;
    // Overlap se bachne ke liye: bolna chal raha ho to pehle roko.
    if (_tts.isSpeaking) {
      await _tts.stop();
    }
    busy = true;
    status = AssistantStatus.listening;
    statusDetail = 'सुन रहा हूँ…';
    partialHeard = '';
    micLevel = 0;
    _safeNotify();

    final bool ok = await _voice.initialize();
    voiceAvailable = ok;
    if (!ok) {
      _finishWithFailure(
        'इस फ़ोन पर स्पीच रिकग्निशन शुरू नहीं हो पाया। '
        '${_voice.lastFailure.hindi}',
      );
      return;
    }

    final String? heard = await _voice.listenOnce(
      localeId: settings.speechLocale,
      onLevel: (double level) {
        micLevel = level.clamp(-2.0, 10.0).toDouble();
        _safeNotify();
      },
      onPartial: (String partial) {
        partialHeard = partial;
        _safeNotify();
      },
    );

    if (heard == null || heard.isEmpty) {
      _finishWithFailure(
        _voice.lastFailure == VoiceFailure.none
            ? 'कुछ सुनाई नहीं दिया।'
            : _voice.lastFailure.hindi,
      );
      return;
    }
    await submitText(heard, fromVoice: true);
  }

  Future<void> stopListening() async {
    await _voice.stop();
    if (status == AssistantStatus.listening) {
      status = AssistantStatus.idle;
      statusDetail = 'रोक दिया';
      _safeNotify();
    }
  }

  // ------------------------------------------------------------- main path

  Future<void> submitText(String raw, {bool fromVoice = false}) async {
    final String text = raw.trim();
    if (text.isEmpty || (busy && status != AssistantStatus.listening)) {
      return;
    }

    // Accidental duplicate command (mic do baar, ya repeat bolna) — skip.
    final DateTime now = DateTime.now();
    final bool duplicate = _lastUserText != null &&
        _lastUserAt != null &&
        now.difference(_lastUserAt!) < duplicateWindow &&
        VoiceService.isDuplicate(_lastUserText!, text);
    _lastUserText = text;
    _lastUserAt = now;
    if (duplicate) {
      status = AssistantStatus.idle;
      statusDetail = 'वो कमांड अभी कर चुके हैं — दोबारा नहीं चलाया';
      _safeNotify();
      return;
    }

    busy = true;
    await _add(ChatMessage(
      id: _id(),
      role: ChatRole.user,
      text: text,
      createdAt: now,
      source: fromVoice ? AnswerSource.device : null,
    ));

    status = AssistantStatus.thinking;
    statusDetail = fromVoice ? 'समझ रहा हूँ…' : 'प्रॉसेस कर रहा हूँ…';
    _safeNotify();

    final Route route = router.route(text);
    switch (route.kind) {
      case RouteKind.repeat:
        await _speakOrShow(_repeatTarget ?? 'दोहराने के लिए कुछ नहीं मिला।',
            source: AnswerSource.localOnly);
      case RouteKind.reply:
        await _speakOrShow(route.replyText!,
            source: AnswerSource.localOnly);
      case RouteKind.tool:
        await _runTool(route.tool!);
      case RouteKind.none:
        if (aiConfigured) {
          // Local router ने जो पहचाना (समय/काम/नियंत्रण) वो ऊपर ही चल गया;
          // बाकी सब online AI के पास — और AI भी वही registry इस्तेमाल करता है।
          await _runAiTurn(text);
          break;
        }
        await _speakOrShow(
          'ये अभी मुझसे नहीं होगा। ऑनलाइन AI अभी बंद है — Settings में Gemini '
          'या कोई OpenAI-compatible provider चुनकर API key डालिए। तब तक मैं '
          'समय/तारीख़ और कामों की लिस्ट का टूल खुद चला सकता हूँ।',
          source: AnswerSource.localOnly,
          failed: true,
        );
    }

    busy = false;
    _safeNotify();
  }

  Future<void> _runTool(ToolRequest request) async {
    final ToolResult result = await registry.execute(request);
    lastToolResults = <ToolResult>[result];
    await _announceToolResult(result);

    if (result.isSuccess) {
      await _speakOrShow(result.spokenText, source: AnswerSource.device);
    } else {
      await _speakOrShow(
        result.spokenText.isEmpty
            ? 'टूल ${result.toolName} सफल नहीं हुआ।'
            : result.spokenText,
        source: AnswerSource.tool,
        failed: true,
      );
    }
  }

  Future<void> _announceToolResult(ToolResult result) => _add(ChatMessage(
        id: _id(),
        role: ChatRole.tool,
        text: result.isSuccess
            ? '${result.toolName} ✓ ${result.spokenText}'.trim()
            : '${result.toolName} ✗ ${result.errorMessage ?? result.outcome.name}',
        createdAt: DateTime.now(),
        source: AnswerSource.tool,
        toolName: result.toolName,
        failed: !result.isSuccess,
      ));

  // ------------------------------------------------------------------- AI
  /// Settings se hi तय hotा है: provider 'off' या key नही = null (tab कभी fake
  /// जवाब नहीं, सिर्फ़ honest error + device tools)।
  AiService? buildAiService() => AiServiceFactory.build(
        provider: aiProvider,
        model: settings.aiModel,
        baseUrl: settings.aiBaseUrl,
        apiKey: _aiKey,
      );

  AiProvider get aiProvider => AiProviderLabel.fromName(settings.aiProvider);

  bool get aiConfigured => aiProvider.isOnline && (_aiKey?.isNotEmpty ?? false);

  String get aiSummary => aiConfigured
      ? '${aiProvider.label} · ${settings.aiModel.trim().isEmpty ? AiConfig.defaultModelFor(aiProvider) : settings.aiModel.trim()}'
      : 'AI बंद — सिर्फ़ डिवाइस पर चलने वाले टूल';

  String get aiKeyMasked => maskSecret(_aiKey ?? '');

  Future<void> _reloadAiKey() async {
    _aiKey = aiProvider.isOnline ? await _keys.read(aiProvider) : null;
  }

  /// Settings से key सेव (validation fail हो तो Hindi error लौटाता है, सेव नहीं होता)।
  Future<String?> saveApiKey(String rawKey) async {
    final String? error = await _keys.save(aiProvider, rawKey);
    await _reloadAiKey();
    _safeNotify();
    return error;
  }

  Future<bool> clearApiKey() async {
    final bool cleared = await _keys.clear(aiProvider);
    await _reloadAiKey();
    _safeNotify();
    return cleared;
  }

  /// "Test API Connection" — असली chhota request, असली latency, असली error।
  Future<AiHealth> testAiConnection() async {
    final AiService? service = buildAiService();
    if (service == null) {
      final AiHealth health = AiHealth(
        ok: false,
        message: aiProvider.isOnline
            ? 'API key सेव नहीं है — पहले key डालिए।'
            : 'पहले Settings में कोई online provider चुनिए।',
        latencyMs: 0,
      );
      lastAiTest = health;
      _safeNotify();
      return health;
    }
    testingAi = true;
    status = AssistantStatus.thinking;
    statusDetail = 'API टेस्ट हो रहा है…';
    _safeNotify();
    try {
      final AiHealth health = await service.healthCheck();
      lastAiTest = health;
      status = health.ok ? AssistantStatus.success : AssistantStatus.error;
      statusDetail = health.message;
      return health;
    } finally {
      testingAi = false;
      service.dispose();
      _safeNotify();
    }
  }

  String _deviceContext() => buildDeviceContext(
        now: DateTime.now(),
        localeLanguage: settings.replyLanguage == 'auto'
            ? settings.speechLocale
            : settings.replyLanguage,
        aiConfigured: aiConfigured,
      );

  Future<void> _runAiTurn(String text) async {
    statusDetail = 'ऑनलाइन मॉडल से पूछ रहा हूँ…';
    _safeNotify();
    final AgentTurn turn = await agent.run(
      text,
      history: messages,
      extraContext: _deviceContext(),
    );
    lastAiToolResults = turn.toolResults;
    lastAiError = turn.errorKind;
    if (turn.toolResults.isNotEmpty) {
      lastToolResults = turn.toolResults;
      for (final ToolResult result in turn.toolResults) {
        await _announceToolResult(result);
      }
    }
    await _speakOrShow(
      turn.reply,
      source: turn.aiAnswered ? AnswerSource.onlineModel : AnswerSource.tool,
      failed: turn.hasError || turn.anyToolFailed,
    );
    if (turn.hasError) {
      final AiErrorKind kind = turn.errorKind!;
      statusDetail = switch (kind) {
        AiErrorKind.rateLimited ||
        AiErrorKind.quotaExhausted =>
          'फ्री सीमा — थोड़ी देर में फिर पूछिए',
        AiErrorKind.invalidKey ||
        AiErrorKind.permissionDenied ||
        AiErrorKind.modelUnavailable =>
          'Settings में key/मॉडल ठीक कीजिए',
        AiErrorKind.network || AiErrorKind.timeout => 'नेटवर्क/टाइमआउट — ऑफ़लाइन mode',
        _ => 'मॉडल से जवाब पूरा नहीं मिला',
      };
    } else if (turn.roundLimitHit || turn.truncated) {
      statusDetail = 'जवाब अधूरा रहा — छोटा दोबारा पूछिए';
    }
    _safeNotify();
  }

  Future<void> _speakOrShow(String text, {
    required AnswerSource source,
    bool failed = false,
  }) async {
    _repeatTarget = text;
    await _add(ChatMessage(
      id: _id(),
      role: ChatRole.assistant,
      text: text,
      createdAt: DateTime.now(),
      source: source,
      failed: failed,
    ));

    if (!settings.autoSpeak) {
      status = failed ? AssistantStatus.error : AssistantStatus.success;
      statusDetail = failed ? 'जवाब पर ध्यान दें' : 'तैयार';
      return;
    }

    status = AssistantStatus.speaking;
    statusDetail = 'बोल रहा हूँ…';
    _safeNotify();
    final bool spoken = await _tts.speak(text);
    lastSpokenText = text;
    if (spoken) {
      status = failed ? AssistantStatus.error : AssistantStatus.success;
      statusDetail = failed ? 'जवाब सुना दिया (गड़बड़ दर्ज है)' : 'पूरा हुआ';
    } else {
      status = AssistantStatus.error;
      statusDetail =
          'आवाज़ नहीं निकल सकी — सेटिंग्स में ${settings.ttsLanguage} का voice '
          'इंस्टॉल/एनेबल करें।';
    }
  }

  void _finishWithFailure(String message) {
    status = AssistantStatus.error;
    statusDetail = message;
    busy = false;
    micLevel = 0;
    _safeNotify();
  }

  // ------------------------------------------------------------ speech ctl

  Future<void> stopSpeaking() async {
    await _tts.stop();
    status = AssistantStatus.idle;
    statusDetail = 'बोलना रोका गया';
    _safeNotify();
  }

  Future<void> repeatLast() async {
    final String? text = _repeatTarget ?? lastSpokenText;
    if (text == null || text.isEmpty) {
      status = AssistantStatus.error;
      statusDetail = 'दोहराने के लिए अभी कोई जवाब नहीं है';
      _safeNotify();
      return;
    }
    status = AssistantStatus.speaking;
    statusDetail = 'फिर से बोल रहा हूँ…';
    _safeNotify();
    await _tts.speak(text);
    status = AssistantStatus.idle;
    _safeNotify();
  }

  // -------------------------------------------------------------- settings

  Future<void> updateSettings(JarvisSettings next) async {
    final bool providerChanged = next.aiProvider != settings.aiProvider;
    settings = next;
    if (providerChanged) {
      // हर provider की key अलग store-key me रहती है।
      await _reloadAiKey();
    }
    memory.enabled = next.rememberHistory;
    await settingsService.save(next);
    await _tts.configure(
      language: next.ttsLanguage,
      rate: next.ttsRate,
      pitch: next.ttsPitch,
    );
    ttsLanguageOk = await _tts.languageInstalled(next.ttsLanguage);
    _safeNotify();
  }

  Future<void> eraseHistory() async {
    await memory.clearHistory();
    messages = <ChatMessage>[];
    _repeatTarget = null;
    lastSpokenText = null;
    statusDetail = 'हिस्टरी मिटा दी गई (सिर्फ़ इस फ़ोन से)';
    _safeNotify();
  }

  /// Test/UI ke liye: "ये सुनो" — TTS ka real check, bina AI ke.
  Future<bool> testVoice() async {
    status = AssistantStatus.speaking;
    statusDetail = 'टेस्ट आवाज़…';
    _safeNotify();
    final bool ok = await _tts.speak('नमस्ते, जार्विस तैयार है।');
    status = ok ? AssistantStatus.success : AssistantStatus.error;
    statusDetail = ok ? 'आवाज़ काम कर रही है' : 'आवाज़ नहीं निकली';
    _safeNotify();
    return ok;
  }

  // ---------------------------------------------------------------- utils

  Future<void> _add(ChatMessage message) async {
    messages = <ChatMessage>[...messages, message];
    await memory.remember(message);
    _safeNotify();
  }

  void _safeNotify() {
    try {
      notifyListeners();
    } on Object {
      // dispose ke baad koi listener nahi — ignore.
    }
  }

  static String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Object().hashCode}';

  @override
  void dispose() {
    _aiKey = null;
    unawaited(_tts.dispose());
    unawaited(_voice.stop());
    super.dispose();
  }
}
