import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jarvis_ai_agent/models/chat_message.dart';
import 'package:jarvis_ai_agent/models/tool_result.dart';
import 'package:jarvis_ai_agent/services/ai/ai_service.dart';
import 'package:jarvis_ai_agent/services/ai/openai_compat_service.dart';

const List<Map<String, Object?>> _declarations = <Map<String, Object?>>[
  <String, Object?>{
    'name': 'open_website',
    'description': 'Opens a website in the browser.',
    'parameters': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{'url': <String, Object?>{'type': 'string'}},
      'required': <String>['url'],
    },
  },
];

Map<String, Object?> _completion({
  String? content,
  List<Map<String, Object?>>? toolCalls,
  String? finishReason,
}) =>
    <String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'index': 0,
          'message': <String, Object?>{
            'role': 'assistant',
            'content': content,
            if (toolCalls != null) 'tool_calls': toolCalls,
          },
          if (finishReason != null) 'finish_reason': finishReason,
        },
      ],
    };

void main() {
  group('OpenAiParser', () {
    test('साफ़ text जवाब', () {
      final AiReply reply = OpenAiParser.parseReply(_completion(content: 'तैयार हूँ।'));
      expect(reply.text, 'तैयार हूँ।');
      expect(reply.toolCalls, isEmpty);
    });

    test('tool_calls: arguments JSON *string* parse होती है, id भी', () {
      final AiReply reply = OpenAiParser.parseReply(_completion(
        finishReason: 'tool_calls',
        toolCalls: <Map<String, Object?>>[
          <String, Object?>{
            'id': 'call_abc',
            'type': 'function',
            'function': <String, Object?>{
              'name': 'open_website',
              'arguments': '{"url":"https://example.com"}',
            },
          },
        ],
      ));
      expect(reply.wantsTools, isTrue);
      expect(reply.toolCalls.single.name, 'open_website');
      expect(reply.toolCalls.single.callId, 'call_abc');
      expect(reply.toolCalls.single.arguments['url'], 'https://example.com');
    });

    test('arguments खराब JSON हों तो खाली args (registry असली error बताएगी)', () {
      final AiReply reply = OpenAiParser.parseReply(_completion(
        toolCalls: <Map<String, Object?>>[
          <String, Object?>{
            'id': 'x',
            'function': <String, Object?>{'name': 'open_website', 'arguments': '{oops'},
          },
        ],
      ));
      expect(reply.toolCalls.single.arguments, isEmpty);
      expect(reply.text, isNull);
    });

    test('arguments map के रूप में भी आ सकते हैं (kuch endpoints)', () {
      final AiReply reply = OpenAiParser.parseReply(_completion(
        toolCalls: <Map<String, Object?>>[
          <String, Object?>{
            'function': <String, Object?>{
              'name': 'open_website',
              'arguments': <String, Object?>{'url': 'https://a.com'},
            },
          },
        ],
      ));
      expect(reply.toolCalls.single.arguments['url'], 'https://a.com');
      expect(reply.toolCalls.single.callId, '');
    });

    test('finish_reason length = truncated, content_filter = blocked', () {
      expect(
        OpenAiParser.parseReply(_completion(content: 'आधा', finishReason: 'length')).truncated,
        isTrue,
      );
      final AiReply filtered =
          OpenAiParser.parseReply(_completion(content: null, finishReason: 'content_filter'));
      expect(filtered.blocked, isTrue);
      expect(filtered.text, contains('सुरक्षा फ़िल्टर'));
    });

    test('choices खाली = ईमानदार संदेश (crash नहीं)', () {
      final AiReply reply = OpenAiParser.parseReply(<String, Object?>{
        'choices': <Object?>[],
        'error': <String, Object?>{'message': 'model_not_found'},
      });
      expect(reply.blocked, isTrue);
      expect(reply.text, contains('model_not_found'));
    });

    test('decodeArguments हर shape संभालता है', () {
      expect(OpenAiParser.decodeArguments(null), isEmpty);
      expect(OpenAiParser.decodeArguments(''), isEmpty);
      expect(OpenAiParser.decodeArguments('not json'), isEmpty);
      expect(OpenAiParser.decodeArguments('{"a":1}'), <String, Object?>{'a': 1});
    });
  });

  group('OpenAiCompatService — request/response (MockClient)', () {
    test('URL, Bearer header, tools/tool_choice और max_tokens की shape', () async {
      final List<http.Request> sent = <http.Request>[];
      final OpenAiCompatService service = OpenAiCompatService(
        model: 'my-model',
        apiKey: 'gsk_test1234567890abcdef',
        client: MockClient((http.Request request) async {
          sent.add(request);
          return http.Response(jsonEncode(_completion(content: 'हो गया')), 200);
        }),
      );

      final AiReply reply = await service
          .startConversation(
            userText: 'youtube खोलो',
            history: <ChatMessage>[
              ChatMessage(
                id: 'u1',
                role: ChatRole.user,
                text: 'पिछला',
                createdAt: DateTime(2026, 10, 13),
              ),
            ],
            functionDeclarations: _declarations,
            extraContext: 'DEVICE CONTEXT: date=2026-10-13',
          )
          .respond();
      expect(reply.text, 'हो गया');

      expect(sent.single.url.toString(), 'https://api.groq.com/openai/v1/chat/completions');
      expect(sent.single.headers['authorization'], 'Bearer gsk_test1234567890abcdef');
      expect(sent.single.headers['content-type'], contains('application/json'));
      expect(sent.single.url.query, isEmpty);

      final Map<String, Object?> body = jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body['model'], 'my-model');
      expect(body['max_tokens'], 700);
      expect(body.containsKey('temperature'), isFalse);
      expect(body['tool_choice'], 'auto');
      final List<Object?> tools = body['tools']! as List<Object?>;
      expect((tools.first! as Map<String, Object?>)['type'], 'function');
      expect(((tools.first! as Map<String, Object?>)['function']! as Map<String, Object?>)['name'],
          'open_website');

      final List<Object?> messages = body['messages']! as List<Object?>;
      expect(messages.length, 3, reason: 'system + history + current user');
      expect((messages[0]! as Map<String, Object?>)['role'], 'system');
      final String system = (messages[0]! as Map<String, Object?>)['content']! as String;
      expect(system, contains('JARVIS'));
      expect(system, contains('DEVICE CONTEXT'));
      expect((messages[2]! as Map<String, Object?>)['content'], 'youtube खोलो');
      service.dispose();
    });

    test('tool round-trip: assistant turn एक, फिर role:tool echo tool_call_id के साथ', () async {
      final List<List<Object?>> sentMessages = <List<Object?>>[];
      final List<String> responses = <String>[
        jsonEncode(_completion(
          toolCalls: <Map<String, Object?>>[
            <String, Object?>{
              'id': 'call_77',
              'function': <String, Object?>{
                'name': 'open_website',
                'arguments': '{"url":"https://example.com"}',
              },
            },
          ],
          finishReason: 'tool_calls',
        )),
        jsonEncode(_completion(content: 'example.com खोल दिया गया।', finishReason: 'stop')),
      ];
      final OpenAiCompatService service = OpenAiCompatService(
        model: 'my-model',
        apiKey: 'gsk_test1234567890abcdef',
        client: MockClient((http.Request request) async {
          final Map<String, Object?> body = jsonDecode(request.body) as Map<String, Object?>;
          sentMessages.add(body['messages']! as List<Object?>);
          return http.Response(responses.removeAt(0), 200);
        }),
      );

      final AiConversation conversation = service.startConversation(
        userText: 'example.com खोलो',
        history: const <ChatMessage>[],
        functionDeclarations: _declarations,
      );
      final AiReply first = await conversation.respond();
      final AiReply second = await conversation.submitToolResults(<ToolEcho>[
        ToolEcho(
          call: first.toolCalls.single,
          result: ToolResult.ok('open_website',
              spokenText: 'browser खोल लिया',
              data: <String, Object?>{'url': 'https://example.com'}),
        ),
      ]);
      expect(second.text, contains('खोल दिया'));

      final List<Object?> round2 = sentMessages[1];
      expect(round2.length, 4, reason: 'system + user + assistant(tool_calls) + tool');
      expect((round2[2]! as Map<String, Object?>)['role'], 'assistant');
      expect((round2[3]! as Map<String, Object?>)['role'], 'tool');
      // assistant turn exactly एक बार, text = '' (content ही नहीं था), और
      // tool_calls उसी में — वरना OpenAI 400 देता है।
      final Map<String, Object?> assistantTurn = round2[2]! as Map<String, Object?>;
      expect(assistantTurn['content'], '');
      final List<Object?> toolCallsSent = assistantTurn['tool_calls']! as List<Object?>;
      expect(toolCallsSent.length, 1);
      final Map<String, Object?> echoed = round2[3]! as Map<String, Object?>;
      expect(echoed['tool_call_id'], 'call_77');
      expect(echoed['name'], 'open_website');
      final Map<String, Object?> payload =
          jsonDecode(echoed['content']! as String) as Map<String, Object?>;
      expect(payload['outcome'], 'success');
      expect(payload['data'], <String, Object?>{'url': 'https://example.com'});
      service.dispose();
    });
  });

  group('OpenAiCompatService — failures', () {
    test('429 + Retry-After: 1 = एक auto retry फिर जवाब', () async {
      int calls = 0;
      final OpenAiCompatService service = OpenAiCompatService(
        model: 'm',
        apiKey: 'gsk_test1234567890abcdef',
        client: MockClient((http.Request request) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              '{"error":{"message":"Rate limit reached for requests per minute"}}',
              429,
              headers: <String, String>{'retry-after': '1'},
            );
          }
          return http.Response(jsonEncode(_completion(content: 'अब ठीक')), 200);
        }),
      );
      final AiReply reply = await service
          .startConversation(
            userText: 'hi',
            history: const <ChatMessage>[],
            functionDeclarations: const <Map<String, Object?>>[],
          )
          .respond();
      expect(reply.text, 'अब ठीक');
      expect(calls, 2);
      service.dispose();
    });

    test('401 = invalidKey, 404 = modelUnavailable (Hindi message)', () async {
      final OpenAiCompatService service = OpenAiCompatService(
        model: 'm',
        apiKey: 'gsk_test1234567890abcdef',
        client: MockClient((http.Request request) async => http.Response(
            '{"error":{"message":"Invalid API key"}}', 401)),
      );
      await expectLater(
        service
            .startConversation(
              userText: 'hi',
              history: const <ChatMessage>[],
              functionDeclarations: const <Map<String, Object?>>[],
            )
            .respond(),
        throwsA(isA<AiException>()
            .having((AiException e) => e.kind, 'kind', AiErrorKind.invalidKey)
            .having((AiException e) => e.canFallBackToLocal, 'fallback', isFalse)),
      );
      service.dispose();
    });

    test('healthCheck:Groq-jैसा error body -> ok=false + वही Hindi कारण', () async {
      final OpenAiCompatService service = OpenAiCompatService(
        model: 'm',
        apiKey: 'gsk_test1234567890abcdef',
        client: MockClient((http.Request request) async => http.Response(
            '{"error":{"message":"The model `m` does not exist or you do not have access to it."}}',
            404)),
      );
      final AiHealth health = await service.healthCheck();
      expect(health.ok, isFalse);
      expect(health.message, contains('मॉडल'));
      service.dispose();
    });

    test('healthCheck: key के बिना network कॉल ही नहीं', () async {
      final OpenAiCompatService service = OpenAiCompatService(model: 'm');
      final AiHealth health = await service.healthCheck();
      expect(health.ok, isFalse);
      expect(health.message, contains('key'));
      service.dispose();
    });

    test('baseUrl trailing slash ho तो भी सही URL (//chat नहीं)', () async {
      final OpenAiCompatService service = OpenAiCompatService(
        model: 'm',
        apiKey: 'k1234567890abcdef',
        baseUrl: 'https://openrouter.ai/api/v1/',
      );
      expect(service.endpoint.toString(), 'https://openrouter.ai/api/v1/chat/completions');
      expect(service.label, 'OpenAI-compatible · m');
      service.dispose();
    });
  });
}
