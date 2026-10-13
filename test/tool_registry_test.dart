import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_ai_agent/models/tool_result.dart';
import 'package:jarvis_ai_agent/services/tool_registry.dart';

class _EchoTool extends JarvisTool {
  _EchoTool()
      : super(
          name: 'echo',
          description: 'test tool',
          params: const <String, ToolParam>{
            'text': ToolParam(type: 'string', description: 'text', maxStringLength: 8),
            'loud': ToolParam(
              type: 'boolean',
              description: 'loud?',
              required: false,
            ),
            'mode': ToolParam(
              type: 'string',
              description: 'mode',
              required: false,
              enumValues: <String>['a', 'b'],
            ),
          },
        );

  int calls = 0;

  @override
  Future<ToolResult> run(ToolRequest request) async {
    calls++;
    return ToolResult.ok('echo', spokenText: '${request['text']}');
  }
}

class _BoomTool extends JarvisTool {
  _BoomTool() : super(name: 'boom', description: 'throws');

  @override
  Future<ToolResult> run(ToolRequest request) =>
      throw StateError('device ne inkaar kar diya');
}

class _ConfirmTool extends JarvisTool {
  _ConfirmTool()
      : super(
          name: 'danger',
          description: 'needs approval',
          requiresConfirmation: true,
          confirmationPrompt: 'पक्का?',
        );

  int calls = 0;

  @override
  Future<ToolResult> run(ToolRequest request) async {
    calls++;
    return ToolResult.ok('danger', spokenText: 'चल गया');
  }
}

void main() {
  group('argument validation', () {
    test('required argument missing -> tool not executed', () async {
      final _EchoTool tool = _EchoTool();
      final ToolRegistry registry = ToolRegistry(<JarvisTool>[tool]);
      final ToolResult r = await registry.execute(
          const ToolRequest(name: 'echo', arguments: <String, Object?>{}));
      expect(r.outcome, ToolOutcome.failure);
      expect(r.errorMessage, contains('`text`'));
      expect(tool.calls, 0, reason: 'validation fail hone par run() nahi chalna chahiye');
    });

    test('unknown argument rejected', () async {
      final ToolRegistry registry = ToolRegistry(<JarvisTool>[_EchoTool()]);
      final ToolResult r = await registry.execute(const ToolRequest(
          name: 'echo',
          arguments: <String, Object?>{'text': 'hi', 'shell': 'rm -rf /'}));
      expect(r.outcome, ToolOutcome.failure);
      expect(r.errorMessage, contains('shell'));
    });

    test('wrong type + enum + length enforced', () async {
      final ToolRegistry registry = ToolRegistry(<JarvisTool>[_EchoTool()]);
      expect(
        (await registry.execute(const ToolRequest(
                name: 'echo', arguments: <String, Object?>{'text': 42})))
            .outcome,
        ToolOutcome.failure,
      );
      expect(
        (await registry.execute(const ToolRequest(
                name: 'echo',
                arguments: <String, Object?>{'text': 'ok', 'mode': 'z'})))
            .outcome,
        ToolOutcome.failure,
      );
      expect(
        (await registry.execute(const ToolRequest(
                name: 'echo',
                arguments: <String, Object?>{'text': '1234567890'})))
            .outcome,
        ToolOutcome.failure,
      );
    });

    test('valid args -> success', () async {
      final _EchoTool tool = _EchoTool();
      final ToolRegistry registry = ToolRegistry(<JarvisTool>[tool]);
      final ToolResult r = await registry.execute(const ToolRequest(
          name: 'echo', arguments: <String, Object?>{'text': 'salaam'}));
      expect(r.isSuccess, isTrue);
      expect(r.spokenText, 'salaam');
      expect(tool.calls, 1);
    });
  });

  test('unknown tool = unsupported, not a fake success', () async {
    final ToolRegistry registry = ToolRegistry(<JarvisTool>[_EchoTool()]);
    final ToolResult r = await registry.execute(const ToolRequest(
        name: 'launch_nukes', arguments: <String, Object?>{}));
    expect(r.outcome, ToolOutcome.unsupported);
    expect(r.isSuccess, isFalse);
  });

  test('tool exception surfaces as failure', () async {
    final ToolRegistry registry = ToolRegistry(<JarvisTool>[_BoomTool()]);
    final ToolResult r = await registry.execute(const ToolRequest(
        name: 'boom', arguments: <String, Object?>{}));
    expect(r.outcome, ToolOutcome.failure);
    expect(r.errorMessage, contains('device ne inkaar'));
  });

  group('confirmation', () {
    test('rejected confirmation -> denied and tool never runs', () async {
      final _ConfirmTool tool = _ConfirmTool();
      final ToolRegistry registry = ToolRegistry(<JarvisTool>[tool]);
      final ToolResult r = await registry.execute(
        const ToolRequest(name: 'danger', arguments: <String, Object?>{}),
        confirm: (JarvisTool t, ToolRequest req) async => false,
      );
      expect(r.outcome, ToolOutcome.denied);
      expect(tool.calls, 0);
    });

    test('approved confirmation -> runs', () async {
      final _ConfirmTool tool = _ConfirmTool();
      final ToolRegistry registry = ToolRegistry(<JarvisTool>[tool]);
      final ToolResult r = await registry.execute(
        const ToolRequest(name: 'danger', arguments: <String, Object?>{}),
        confirm: (JarvisTool t, ToolRequest req) async => true,
      );
      expect(r.isSuccess, isTrue);
      expect(tool.calls, 1);
    });
  });

  test('duplicate tool name is a programming error', () {
    expect(
      () => ToolRegistry(<JarvisTool>[_EchoTool(), _EchoTool()]),
      throwsA(isA<StateError>()),
    );
  });

  test('function declarations expose required params for the AI layer', () {
    final ToolRegistry registry = ToolRegistry(<JarvisTool>[_EchoTool()]);
    final Map<String, Object?> decl = registry.functionDeclarations().single;
    expect(decl['name'], 'echo');
    final Map<String, Object?> params = decl['parameters']! as Map<String, Object?>;
    expect(params['required'], <String>['text']);
    expect((params['properties']! as Map<String, Object?>).keys,
        containsAll(<String>['text', 'loud', 'mode']));
  });
}
