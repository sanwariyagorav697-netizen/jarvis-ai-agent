import '../../models/chat_message.dart';
import '../../models/tool_result.dart';
import '../tool_registry.dart';
import 'ai_service.dart';

/// Ek user turn ka AI natija — jawab, चले हुए टूल, और (दिक्कत हो तो) साफ़
/// error category + Hindi संदेश।
///
/// [reply] कभी fake नहीं hotा: या तो model का असली जवाब, या चले हुए टूल का
/// असली result, या "यह नहीं हो पाया" + कारण।
class AgentTurn {
  const AgentTurn({
    required this.reply,
    this.toolResults = const <ToolResult>[],
    this.errorKind,
    this.errorMessage,
    this.retryAfter,
    this.aiAnswered = false,
    this.truncated = false,
    this.blocked = false,
    this.canFallBackToLocal = false,
    this.roundLimitHit = false,
  });

  final String reply;
  final List<ToolResult> toolResults;
  final AiErrorKind? errorKind;
  final String? errorMessage;
  final Duration? retryAfter;

  /// true = online model ने खुद text भेजा (UI "ऑनलाइन मॉडल से" label दिखता है)।
  final bool aiAnswered;

  /// true = maxOutputTokens पर जवाब कट गया।
  final bool truncated;

  /// true = safety filter ने रोक दिया।
  final bool blocked;

  /// true = ऐसी दिक्कत जिसमें device-only जवाब इमानदारी से दिया जा सकता है।
  final bool canFallBackToLocal;

  /// true = model और tools माँग रहा था, par round limit (3) भर हो गई।
  final bool roundLimitHit;

  bool get hasError => errorKind != null;

  bool get toolsAllSucceeded =>
      toolResults.isNotEmpty &&
      toolResults.every((ToolResult r) => r.isSuccess);

  bool get anyToolFailed =>
      toolResults.any((ToolResult r) => !r.isSuccess);

  List<String> get toolNames =>
      toolResults.map((ToolResult r) => r.toolName).toList(growable: false);
}

/// AI + tools का orchestrator.
///
/// Ye khud कभी कुछ नहीं चलाता: model sirf tool *माँगता* है, और हर call
/// [ToolRegistry] से ही गुज़रती है (argument validation + confirmation + असली
/// result). इसीलिए एक खराब/garbage JSON भी device पर मनमानी नहीं कर सकता।
class JarvisAgent {
  JarvisAgent({
    required this.registry,
    required this.serviceBuilder,
  });

  final ToolRegistry registry;

  /// हर turn पर fresh service बनती है, ताकि Settings में provider/model/key
  /// बदलते ही app restart के बिना लागू हो जाए। Turn खत्म होते ही dispose।
  final AiService? Function() serviceBuilder;

  Future<AgentTurn> run(
    String userText, {
    required List<ChatMessage> history,
    required String extraContext,
    ConfirmationHandler? confirm,
  }) async {
    final AiService? service = serviceBuilder();
    if (service == null) {
      return const AgentTurn(
        reply: '',
        errorKind: AiErrorKind.notConfigured,
        errorMessage:
            'AI अभी सेट नहीं है। Settings में provider चुनकर API key डालिए।',
        canFallBackToLocal: true,
      );
    }
    try {
      return await _runWith(service, userText, history, extraContext, confirm);
    } finally {
      service.dispose();
    }
  }

  Future<AgentTurn> _runWith(
    AiService service,
    String userText,
    List<ChatMessage> history,
    String extraContext,
    ConfirmationHandler? confirm,
  ) async {
    final AiConversation conversation = service.startConversation(
      userText: userText,
      history: history,
      functionDeclarations: registry.functionDeclarations(),
      extraContext: extraContext,
    );

    final List<ToolResult> toolResults = <ToolResult>[];
    final List<String> spokenParts = <String>[];
    bool truncated = false;
    bool blocked = false;
    bool roundLimitHit = false;

    try {
      AiReply reply = await conversation.respond();
      for (int round = 0; round <= AiConversation.maxToolRounds; round++) {
        final String? text = reply.text;
        if (text != null && text.trim().isNotEmpty) {
          spokenParts.add(text.trim());
        }
        truncated = reply.truncated;
        blocked = blocked || reply.blocked;
        if (!reply.wantsTools) {
          break;
        }
        if (round == AiConversation.maxToolRounds) {
          roundLimitHit = true;
          break;
        }
        final List<ToolEcho> echoes = <ToolEcho>[];
        for (final AiToolCall call in reply.toolCalls) {
          // Ek hi जगह से execution — registry validation/confirmation khud करती है।
          final ToolResult result = await registry.execute(
            ToolRequest(name: call.name, arguments: call.arguments),
            confirm: confirm,
          );
          toolResults.add(result);
          echoes.add(ToolEcho(call: call, result: result));
        }
        reply = await conversation.submitToolResults(echoes);
      }

      String text = spokenParts.join(' ').trim();
      if (text.isEmpty && toolResults.isNotEmpty) {
        // Model आखिर में चुप रहा, par टूल चले: टूल का असली जवाब ही सुनाएँगे
        // (कोई बनावटी संयोग नहीं)।
        text = toolResults
            .map((ToolResult r) => r.spokenText.trim())
            .where((String s) => s.isNotEmpty)
            .join(' ')
            .trim();
      }
      if (text.isEmpty) {
        text = blocked
            ? 'मॉडल ने यह जवाब देने से इनकार कर दिया। शब्द बदलकर दोबारा पूछिए।'
            : 'मॉडल से खाली जवाब आया। दोबारा पूछिए, न बने तो Settings में दूसरा मॉडल चुनिए।';
      }
      if (truncated) {
        text = '$text (जवाब लंबा होने से कट गया — छोटा पूछिए)';
      }
      if (roundLimitHit) {
        text = '$text (एक बार में 3 tool rounds के बाद रुक गया — बाकी दोबारा पूछिए)';
      }
      return AgentTurn(
        reply: text,
        toolResults: toolResults,
        aiAnswered: spokenParts.isNotEmpty,
        truncated: truncated,
        blocked: blocked,
        roundLimitHit: roundLimitHit,
      );
    } on AiException catch (failure) {
      final String partial = spokenParts.join(' ').trim();
      final String toolNote = toolResults.isEmpty
          ? ''
          : ' जो टूल चल चुके थे: ${toolResults.map((ToolResult r) => r.toolName).join(', ')}।';
      return AgentTurn(
        reply: partial.isEmpty ? failure.message : '$partial\n${failure.message}',
        toolResults: toolResults,
        errorKind: failure.kind,
        errorMessage: failure.message,
        retryAfter: failure.retryAfter,
        aiAnswered: partial.isNotEmpty,
        blocked: failure.kind == AiErrorKind.blocked,
        canFallBackToLocal: failure.canFallBackToLocal,
      );
    } on Object catch (error) {
      // Anjaan failure = इमानदार error, कभी "हो गया" नहीं।
      return AgentTurn(
        reply: 'मॉडल का जवाब समझ नहीं आया, इसलिए मैंने इससे आगे कुछ नहीं किया। '
            '(${clip('$error')})',
        toolResults: toolResults,
        errorKind: AiErrorKind.badResponse,
        errorMessage: 'उम्मीद से अलग जवाब आया।',
        canFallBackToLocal: true,
      );
    }
  }
}
