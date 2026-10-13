import 'package:shared_preferences/shared_preferences.dart';

/// App ki poori user-controlled settings. Sab kuch device par rehta hai
/// (SharedPreferences), kuch bhi network par nahi jata — API key alag se
/// secure storage me jayegi (Phase 4), yahan nahi.
class JarvisSettings {
  const JarvisSettings({
    this.replyLanguage = 'auto',
    this.speechLocale = 'hi_IN',
    this.ttsLanguage = 'hi-IN',
    this.ttsRate = 0.5,
    this.ttsPitch = 1.0,
    this.autoSpeak = true,
    this.rememberHistory = true,
    this.aiProvider = 'off',
    this.aiModel = '',
    this.aiBaseUrl = '',
  });

  /// 'auto' = jo bhasha user bola, wahi; 'hi' | 'en' = force.
  final String replyLanguage;

  /// Android SpeechRecognizer ka locale (underscore wala format).
  final String speechLocale;

  /// TextToSpeech ka locale (hyphen wala format).
  final String ttsLanguage;

  /// flutter_tts ka rate 0.0..1.0 (Android par 0.5 = normal).
  final double ttsRate;
  final double ttsPitch;

  /// false karne par jawab sirf screen par aayega, bola nahi jayega.
  final bool autoSpeak;

  /// false = conversation history save nahi hogi (app band karte hi sab delete).
  final bool rememberHistory;

  /// 'off' | 'gemini' | 'openaiCompatible' — online AI provider. API key yahan
  /// कभी नहीं जाती (wo secure storage me rehti है); ye sirf *kaun sa* provider
  /// है यही बताता है।
  final String aiProvider;

  /// '' = us provider का default model. Google naye model naam deta रहता है,
  /// इसलिए ye field user बदल सकता है (Settings me editable)।
  final String aiModel;

  /// OpenAI-compatible endpoints के लिए base URL; '' = built-in default।
  final String aiBaseUrl;

  JarvisSettings copyWith({
    String? replyLanguage,
    String? speechLocale,
    String? ttsLanguage,
    double? ttsRate,
    double? ttsPitch,
    bool? autoSpeak,
    bool? rememberHistory,
    String? aiProvider,
    String? aiModel,
    String? aiBaseUrl,
  }) {
    return JarvisSettings(
      replyLanguage: replyLanguage ?? this.replyLanguage,
      speechLocale: speechLocale ?? this.speechLocale,
      ttsLanguage: ttsLanguage ?? this.ttsLanguage,
      ttsRate: ttsRate ?? this.ttsRate,
      ttsPitch: ttsPitch ?? this.ttsPitch,
      autoSpeak: autoSpeak ?? this.autoSpeak,
      rememberHistory: rememberHistory ?? this.rememberHistory,
      aiProvider: aiProvider ?? this.aiProvider,
      aiModel: aiModel ?? this.aiModel,
      aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
    );
  }

  bool get speakHindi => !ttsLanguage.startsWith('en');
}

class SettingsService {
  SettingsService({SharedPreferences? prefs}) : _prefs = prefs;

  static const String kReplyLanguage = 'jarvis.reply_language';
  static const String kSpeechLocale = 'jarvis.speech_locale';
  static const String kTtsLanguage = 'jarvis.tts_language';
  static const String kTtsRate = 'jarvis.tts_rate';
  static const String kTtsPitch = 'jarvis.tts_pitch';
  static const String kAutoSpeak = 'jarvis.auto_speak';
  static const String kRememberHistory = 'jarvis.remember_history';
  static const String kAiProvider = 'jarvis.ai_provider';
  static const String kAiModel = 'jarvis.ai_model';
  static const String kAiBaseUrl = 'jarvis.ai_base_url';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _store() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<JarvisSettings> load() async {
    final SharedPreferences p = await _store();
    const JarvisSettings d = JarvisSettings();
    return JarvisSettings(
      replyLanguage: p.getString(kReplyLanguage) ?? d.replyLanguage,
      speechLocale: p.getString(kSpeechLocale) ?? d.speechLocale,
      ttsLanguage: p.getString(kTtsLanguage) ?? d.ttsLanguage,
      ttsRate: (p.getDouble(kTtsRate) ?? d.ttsRate).clamp(0.2, 1.0).toDouble(),
      ttsPitch: (p.getDouble(kTtsPitch) ?? d.ttsPitch).clamp(0.5, 2.0).toDouble(),
      autoSpeak: p.getBool(kAutoSpeak) ?? d.autoSpeak,
      rememberHistory: p.getBool(kRememberHistory) ?? d.rememberHistory,
      aiProvider: p.getString(kAiProvider) ?? d.aiProvider,
      aiModel: p.getString(kAiModel) ?? d.aiModel,
      aiBaseUrl: p.getString(kAiBaseUrl) ?? d.aiBaseUrl,
    );
  }

  Future<void> save(JarvisSettings s) async {
    final SharedPreferences p = await _store();
    await p.setString(kReplyLanguage, s.replyLanguage);
    await p.setString(kSpeechLocale, s.speechLocale);
    await p.setString(kTtsLanguage, s.ttsLanguage);
    await p.setDouble(kTtsRate, s.ttsRate);
    await p.setDouble(kTtsPitch, s.ttsPitch);
    await p.setBool(kAutoSpeak, s.autoSpeak);
    await p.setBool(kRememberHistory, s.rememberHistory);
    await p.setString(kAiProvider, s.aiProvider);
    await p.setString(kAiModel, s.aiModel.trim());
    await p.setString(kAiBaseUrl, s.aiBaseUrl.trim());
  }
}
