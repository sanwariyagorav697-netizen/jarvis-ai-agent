import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_ai_agent/models/chat_message.dart';
import 'package:jarvis_ai_agent/models/tool_result.dart';
import 'package:jarvis_ai_agent/services/ai/ai_service.dart';
import 'package:jarvis_ai_agent/services/ai/jarvis_agent.dart';
import 'package:jarvis_ai_agent/services/tool_registry.dart';
import 'package:jarvis_ai_agent/tools/current_time_tool.dart';

/// एक tool जो रिकॉर्ड करता है कि उसे क्या-क्या भेजा गया — इसी से verify करते
/// हैं कि AI का "कमांड" सिर्फ़ registry के रास्ते ही चलता है।
class _SpyTool extends JarvisTool {
  // नाम जान-बूझकर super ctor से अलग रखे हैं (toolName/needsConfirm/...) —
  // वरना `use_super_parameters` lint हर जगह टकराता है।
  _SpyTool({
    String toolName = 'get_current_time',
    this.outcome = ToolOutcome.success,
    this.why = '',
    this.spoken = 'टूल का असली जवाब',
    bool needsConfirm = false,
    String confirmPrompt = '',
  }) : super(
          name: toolName,
          description: 'test spy tool',
          requiresConfirmation: needsConfirm,
          confirmationPrompt: confirmPrompt,
          params: const <String, ToolParam>{
            'text': ToolParam(type: 'string', description: 'kuch', required: false),
          },
        );

  final ToolOutcome outcome;
  final String why;
  final String spoken;
  final List<ToolRequest> received = <ToolRequest>[];

  @override
  Future<ToolResult> run(ToolRequest request) async {
    received.add(request);
    switch (outcome) {
      case ToolOutcome.failure:
        return ToolResult.fail(name, why);
      case ToolOutcome.denied:
        return ToolResult.denied(name, why);
      case ToolOutcome.unsupported:
        return ToolResult.unsupported(name, why);
      case ToolOutcome.notImplemented:
        return ToolResult.notImplemented(name, why);
      case ToolOutcome.success:
        return ToolResult.ok(name, spokenText: spoken, data: <String, Object?>{'ran': 1});
    }
  }
}

class _FakeService implements AiService {
  _FakeService({
    this.replies = const <AiReply>[],
    this.repeat,
    this.error,
    this.errorAt = 1,
  });

  final List<AiReply> replies;
  final AiReply? repeat;

  /// कौन-से call पर exception फेंकना है (1 = पहला) — ताकि "आधा काम हो चुका है"
  /// वाली branch भी test हो सके।
  final int errorAt;
  final Object? error;

  int disposed = 0;
  int calls = 0;
  _FakeConversation? lastConversation;
  String? lastUserText;
  String? lastExtraContext;
  List<ChatMessage>? lastHistory;
  List<Map<String, Object?>>? lastDeclarations;

  @override
  String get label => 'Fake · test';

  @override
  bool get isConfigured => true;

  @override
  AiConversation startConversation({
    required String userText,
    required List<ChatMessage> history,
    required List<Map<String, Object?>> functionDeclarations,
    String? extraContext,
  }) {
    lastUserText = userText;
    lastHistory = history;
    lastDeclarations = functionDeclarations;
    lastExtraContext = extraContext;
    return lastConversation = _FakeConversation(this);
  }

  @override
  Future<AiHealth> healthCheck() async =>
      const AiHealth(ok: true, message: 'fake ok', latencyMs: 1);

  @override
  void dispose() {
    disposed++;
  }

  AiReply next() {
    calls++;
    if (error != null && calls == errorAt) {
      throw error!;
    }
    if (calls <= replies.length) {
      return replies[calls - 1];
    }
    return repeat ?? const AiReply(text: 'बाकी कुछ नहीं (script खत्म)');
  }
}

class _FakeConversation implements AiConversation {
  _FakeConversation(this.service);

  final _FakeService service;
  final List<ToolEcho> submitted = <ToolEcho>[];

  @override
  Future<AiReply> respond() async => service.next();

  @override
  Future<AiReply> submitToolResults(List<ToolEcho> results) async {
    submitted.addAll(results);
    return service.next();
  }

  @override
  Map<String, Object?> debugRequestPreview() => <String, Object?>{
        'calls': service.calls,
        'submitted': submitted.length,
      };
}

void main() {
  const AiToolCall timeCall = AiToolCall(
    name: 'get_current_time',
    arguments: <String, Object?>{'info': 'date'},
    callId: 'c1',
  );

  JarvisAgent buildAgent({required AiService? Function() builder, ToolRegistry? registry}) =>
      JarvisAgent(registry: registry ?? ToolRegistry(<JarvisTool>[CurrentTimeTool()]), serviceBuilder: builder);

  group('JarvisAgent — AI band/अनकन्फियर्ड', () {
    test('service null हो तो नकली जवाब नहीं — Settings भेजने का संदेश', () async {
      final JarvisAgent agent = buildAgent(builder: () => null);
      final AgentTurn turn = await agent.run('कुछ भी',
          history: const <ChatMessage>[], extraContext: 'ctx');
      expect(turn.errorKind, AiErrorKind.notConfigured);
      expect(turn.reply, contains('Settings'));
      expect(turn.canFallBackToLocal, isTrue);
      expect(turn.aiAnswered, isFalse);
      expect(turn.toolResults, isEmpty);
    });
  });

  group('JarvisAgent — सादा जवाब', () {
    test('model का text जवाब वैसा ही आता है, service dispose भी होती है', () async {
      final _FakeService service =
          _FakeService(replies: const <AiReply>[AiReply(text: 'मैं ठीक हूँ, पूछिए।')]);
      final JarvisAgent agent = buildAgent(builder: () => service);

      final AgentTurn turn = await agent.run(
        'कैसे हो?',
        history: <ChatMessage>[
          ChatMessage(id: 'u', role: ChatRole.user, text: 'hi', createdAt: DateTime(2026)),
        ],
        extraContext: 'DEVICE CONTEXT: date=2026-10-13',
      );

      expect(turn.reply, 'मैं ठीक हूँ, पूछिए।');
      expect(turn.aiAnswered, isTrue);
      expect(turn.hasError, isFalse);
      expect(service.disposed, 1, reason: 'हर turn के बाद client बंद (resource leak नहीं)');
      expect(service.lastUserText, 'कैसे हो?');
      expect(service.lastExtraContext, contains('DEVICE CONTEXT'));
      expect(service.lastHistory!.single.text, 'hi');
      expect(service.lastDeclarations!.first['name'], 'get_current_time');
    });

    test('truncated जवाब पर UI note जुड़ता है (छोटा पूछने को बोले)', () async {
      final _FakeService service = _FakeService(
          replies: const <AiReply>[AiReply(text: 'लंबा जवाब', truncated: true)]);
      final AgentTurn turn =
          await buildAgent(builder: () => service).run('बताओ',
              history: const <ChatMessage>[], extraContext: '');
      expect(turn.truncated, isTrue);
      expect(turn.reply, contains('कट गया'));
    });

    test('blocked जवाब पर safety का साफ़ संदेश', () async {
      final _FakeService service = _FakeService(
          replies: const <AiReply>[AiReply(blocked: true)]);
      final AgentTurn turn = await buildAgent(builder: () => service).run('बताओ',
          history: const <ChatMessage>[], extraContext: '');
      expect(turn.blocked, isTrue);
      expect(turn.reply, contains('इनकार'));
    });
  });

  group('JarvisAgent — tool calling', () {
    test('model का call registry से चलता है, args वही जाते हैं, अंतिम जवाब model का', () async {
      final _SpyTool tool = _SpyTool(spoken: '11 अक्टूबर 2026');
      final JarvisAgent agent = buildAgent(
        registry: ToolRegistry(<JarvisTool>[tool]),
        builder: () => _FakeService(replies: const <AiReply>[
          AiReply(toolCalls: <AiToolCall>[timeCall]),
          AiReply(text: 'तारीख़: 11 अक्टूबर 2026'),
        ]),
      );

      final AgentTurn turn = await agent.run('आज कौन सा दिन है?',
          history: const <ChatMessage>[], extraContext: '');

      expect(tool.received.single.arguments['info'], 'date');
      expect(turn.reply, 'तारीख़: 11 अक्टूबर 2026');
      expect(turn.toolResults.single.isSuccess, isTrue);
      expect(turn.toolsAllSucceeded, isTrue);
      expect(turn.toolNames, <String>['get_current_time']);
    });

    test('model tool के बाद चुप रहे तो टूल का असली जवाब सुनाया जाता है', () async {
      final _SpyTool tool = _SpyTool(spoken: 'रविवार, 11 अक्टूबर 2026');
      final JarvisAgent agent = buildAgent(
        registry: ToolRegistry(<JarvisTool>[tool]),
        builder: () => _FakeService(replies: const <AiReply>[
          AiReply(toolCalls: <AiToolCall>[timeCall]),
        ]),
      );
      final AgentTurn turn = await agent.run('तारीख़?',
          history: const <ChatMessage>[], extraContext: '');
      expect(turn.reply, contains('रविवार'));
      expect(turn.aiAnswered, isFalse, reason: 'text model का नहीं, tool का है');
    });

    test('tool fail हो तो जवाब में असली failure दिखती है (झूठा success नहीं)', () async {
      final _SpyTool tool = _SpyTool(
        outcome: ToolOutcome.failure,
        why: 'घड़ी पढ़ने में दिक्कत',
      );
      final JarvisAgent agent = buildAgent(
        registry: ToolRegistry(<JarvisTool>[tool]),
        builder: () => _FakeService(replies: const <AiReply>[
          AiReply(toolCalls: <AiToolCall>[timeCall]),
        ]),
      );
      final AgentTurn turn = await agent.run('तारीख़?',
          history: const <ChatMessage>[], extraContext: '');
      expect(turn.anyToolFailed, isTrue);
      expect(turn.toolsAllSucceeded, isFalse);
      expect(turn.reply, contains('दिक्कत'));
      expect(turn.toolResults.single.outcome, ToolOutcome.failure);
    });

    test('model ने ऐसा tool माँगा जो है नहीं → registry reject करती है, कुछ नहीं चलता', () async {
      final _SpyTool tool = _SpyTool();
      final JarvisAgent agent = buildAgent(
        registry: ToolRegistry(<JarvisTool>[tool]),
        builder: () => _FakeService(replies: const <AiReply>[
          AiReply(toolCalls: <AiToolCall>[
            AiToolCall(
              name: 'delete_all_files',
              arguments: <String, Object?>{},
              callId: 'evil',
            ),
          ]),
          AiReply(text: 'वो टूल मेरे पास नहीं है।'),
        ]),
      );
      final AgentTurn turn = await agent.run('सारे फाइल हटाओ',
          history: const <ChatMessage>[], extraContext: '');
      expect(tool.received, isEmpty, reason: 'अनजान tool कभी execute नहीं होता');
      expect(turn.toolResults.single.outcome, ToolOutcome.unsupported);
      expect(turn.reply, 'वो टूल मेरे पास नहीं है।');
    });

    test('sensitive tool: user ने इनकार किया तो denied रिकॉर्ड होता है, काम नहीं चलता', () async {
      final _SpyTool tool = _SpyTool(needsConfirm: true, confirmPrompt: 'पक्का?');
      int asked = 0;
      final JarvisAgent agent = buildAgent(
        registry: ToolRegistry(<JarvisTool>[tool]),
        builder: () => _FakeService(replies: const <AiReply>[
          AiReply(toolCalls: <AiToolCall>[timeCall]),
          AiReply(text: 'ठीक है, नहीं किया।'),
        ]),
      );
      final AgentTurn turn = await agent.run('तारीख़ दिखाओ',
          history: const <ChatMessage>[],
          extraContext: '',
          confirm: (JarvisTool t, ToolRequest r) async {
            asked++;
            return false;
          });
      expect(asked, 1, reason: 'पुष्टि dialog एक बार ही (AI से double-prompt नहीं)');
      expect(tool.received, isEmpty);
      expect(turn.toolResults.single.outcome, ToolOutcome.denied);
    });

    test('हर बार का tool echo असली result payload भेजता है', () async {
      final _FakeService service = _FakeService(replies: const <AiReply>[
        AiReply(toolCalls: <AiToolCall>[timeCall]),
        AiReply(text: 'ठीक'),
      ]);
      final JarvisAgent agent = buildAgent(
        registry: ToolRegistry(<JarvisTool>[_SpyTool()]),
        builder: () => service,
      );
      await agent.run('तारीख़', history: const <ChatMessage>[], extraContext: '');
      final List<ToolEcho> echoes = service.lastConversation!.submitted;
      expect(echoes, hasLength(1));
      expect(echoes.single.call.callId, 'c1');
      expect(echoes.single.call.name, 'get_current_time');
      expect(echoes.single.payload['outcome'], 'success');
      expect(echoes.single.result.spokenText, 'टूल का असली जवाब');
      expect(echoes.single.displayLine, contains('get_current_time'));
      expect(service.lastConversation!.debugRequestPreview()['submitted'], 1);
    });

    test('model बार-बार tool माँगे तो 3 rounds के बाद रुकता है (infinite loop नहीं)', () async {
      final _SpyTool tool = _SpyTool();
      int executed = 0;
      final JarvisAgent agent = buildAgent(
        registry: ToolRegistry(<JarvisTool>[_CountingTool(onRun: () => executed++)]),
        builder: () => _FakeService(repeat: const AiReply(toolCalls: <AiToolCall>[timeCall])),
      );
      final AgentTurn turn = await agent.run('गिनती करो',
          history: const <ChatMessage>[], extraContext: '');
      expect(executed, AiConversation.maxToolRounds);
      expect(tool.received, isEmpty);
      expect(turn.roundLimitHit, isTrue);
      expect(turn.reply, contains('3 tool rounds'));
      expect(turn.toolResults, hasLength(3));
    });
  });

  group('JarvisAgent — failures', () {
    test('AiException (quota) → kind + Hindi message + local fallback लायक', () async {
      final JarvisAgent agent = buildAgent(
        builder: () => _FakeService(
          error: const AiException(
            kind: AiErrorKind.quotaExhausted,
            message: 'आज का फ्री quota खत्म हो गया है।',
          ),
        ),
      );
      final AgentTurn turn = await agent.run('बताओ',
          history: const <ChatMessage>[], extraContext: '');
      expect(turn.errorKind, AiErrorKind.quotaExhausted);
      expect(turn.errorMessage, contains('quota'));
      expect(turn.reply, contains('quota'));
      expect(turn.canFallBackToLocal, isTrue);
      expect(turn.aiAnswered, isFalse);
    });

    test('quota + चल चुका tool → जवाब में दोनों की सच्ची रिपोर्ट', () async {
      final JarvisAgent agent = buildAgent(
        registry: ToolRegistry(<JarvisTool>[_SpyTool(spoken: 'रविवार')]),
        builder: () => _FakeService(
          replies: const <AiReply>[AiReply(toolCalls: <AiToolCall>[timeCall])],
          errorAt: 2,
          error: const AiException(
            kind: AiErrorKind.rateLimited,
            message: 'फ्री tier की प्रति-मिनट सीमा भर गई है।',
            retryAfter: Duration(seconds: 9),
          ),
        ),
      );
      // error दूसरे call पर = tool चल चुका है, फिर नेट चला गया
      final AgentTurn turn = await agent.run('तारीख़',
          history: const <ChatMessage>[], extraContext: '');
      expect(turn.errorKind, AiErrorKind.rateLimited);
      expect(turn.retryAfter, const Duration(seconds: 9));
      expect(turn.reply, contains('प्रति-मिनट'));
      expect(turn.toolResults, hasLength(1));
      expect(turn.reply, contains('चले हुए टूल: get_current_time'));
    });

    test('अनजान exception → badResponse + "आगे कुछ नहीं किया" (crash नहीं)', () async {
      final JarvisAgent agent = buildAgent(
        builder: () => _FakeService(error: StateError('bad json')),
      );
      final AgentTurn turn = await agent.run('बताओ',
          history: const <ChatMessage>[], extraContext: '');
      expect(turn.errorKind, AiErrorKind.badResponse);
      expect(turn.reply, contains('कुछ नहीं किया'));
    });
  });
}

class _CountingTool extends JarvisTool {
  _CountingTool({required this.onRun})
      : super(name: 'get_current_time', description: 'counting spy');

  final void Function() onRun;

  @override
  Future<ToolResult> run(ToolRequest request) async {
    onRun();
    return ToolResult.ok('get_current_time', spokenText: 'चल गया');
  }
}
