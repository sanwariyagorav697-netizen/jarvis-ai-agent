import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jarvis_ai_agent/models/chat_message.dart';
import 'package:jarvis_ai_agent/models/tool_result.dart';
import 'package:jarvis_ai_agent/services/ai/ai_service.dart';
import 'package:jarvis_ai_agent/services/ai/gemini_service.dart';

const List<Map<String, Object?>> _declarations = <Map<String, Object?>>[
  <String, Object?>{
    'name': 'get_current_time',
    'description': 'Device ki date/time batata hai.',
    'parameters': <String, Object?>{'type': 'object', 'properties': <String, Object?>{}},
  },
];

ChatMessage _user(String text) => ChatMessage(
      id: 'u-$text',
      role: ChatRole.user,
      text: text,
      createdAt: DateTime(2026, 10, 13),
    );

Map<String, Object?> _replyJson({String? text, List<Map<String, Object?>>? calls, String? finishReason}) {
  return <String, Object?>{
    'candidates': <Object?>[
      <String, Object?>{
        'content': <String, Object?>{
          'role': 'model',
          'parts': <Object?>[
            if (text != null) <String, Object?>{'text': text},
            for (final Map<String, Object?> call in calls ?? const <Map<String, Object?>>[])
              <String, Object?>{'functionCall': call},
          ],
        },
        if (finishReason != null) 'finishReason': finishReason,
      },
    ],
  };
}

void main() {
  group('GeminiParser', () {
    test('साफ़ text जवाब', () {
      final AiReply reply = GeminiParser.parseReply(_replyJson(text: 'नमस्ते।'));
      expect(reply.text, 'नमस्ते।');
      expect(reply.toolCalls, isEmpty);
      expect(reply.blocked, isFalse);
      expect(reply.truncated, isFalse);
    });

    test('functionCall parts + id (Gemini 3 का functionCallId)', () {
      final AiReply reply = GeminiParser.parseReply(_replyJson(
        calls: <Map<String, Object?>>[
          <String, Object?>{
            'id': 'call_1',
            'name': 'get_current_time',
            'args': <String, Object?>{'info': 'time'},
          },
        ],
      ));
      expect(reply.wantsTools, isTrue);
      expect(reply.toolCalls.single.name, 'get_current_time');
      expect(reply.toolCalls.single.callId, 'call_1');
      expect(reply.toolCalls.single.arguments['info'], 'time');
    });

    test('text + functionCall एक ही turn में dono पढ़े जाते हैं', () {
      final AiReply reply = GeminiParser.parseReply(<String, Object?>{
        'candidates': <Object?>[
          <String, Object?>{
            'content': <String, Object?>{
              'role': 'model',
              'parts': <Object?>[
                <String, Object?>{'text': 'एक काम करता हूँ।'},
                <String, Object?>{
                  'functionCall': <String, Object?>{'name': 'get_current_time', 'args': <String, Object?>{}},
                },
              ],
            },
          },
        ],
      });
      expect(reply.text, 'एक काम करता हूँ।');
      expect(reply.toolCalls.length, 1);
    });

    test('thought (thinking) parts display में नहीं जाते', () {
      final AiReply reply = GeminiParser.parseReply(<String, Object?>{
        'candidates': <Object?>[
          <String, Object?>{
            'content': <String, Object?>{
              'role': 'model',
              'parts': <Object?>[
                <String, Object?>{'text': 'soch raha hoon...', 'thought': true},
                <String, Object?>{'text': 'असली जवाब।'},
              ],
            },
          },
        ],
      });
      expect(reply.text, 'असली जवाब।');
    });

    test('args गायब हों तो खाली map (tool की validation असली error बताएगी)', () {
      final AiReply reply = GeminiParser.parseReply(_replyJson(
        calls: <Map<String, Object?>>[
          <String, Object?>{'name': 'get_current_time'},
        ],
      ));
      expect(reply.toolCalls.single.arguments, isEmpty);
    });

    test('max_tokens = truncated, safety = blocked + Hindi संदेश', () {
      expect(GeminiParser.parseReply(_replyJson(text: 'आधा', finishReason: 'MAX_TOKENS')).truncated, isTrue);
      final AiReply blocked = GeminiParser.parseReply(<String, Object?>{
        'candidates': <Object?>[
          <String, Object?>{'content': <String, Object?>{'parts': <Object?>[]}, 'finishReason': 'SAFETY'},
        ],
      });
      expect(blocked.blocked, isTrue);
      expect(blocked.text, contains('सुरक्षा फ़िल्टर'));
    });

    test('candidates खाली + promptFeedback.blockReason', () {
      final AiReply reply = GeminiParser.parseReply(<String, Object?>{
        'promptFeedback': <String, Object?>{'blockReason': 'BLOCKLIST'},
      });
      expect(reply.blocked, isTrue);
      expect(reply.text, contains('सुरक्षा फ़िल्टर'));
    });

    test('अजीब shape पर crash नहीं, ईमानदार संदेश', () {
      final AiReply reply = GeminiParser.parseReply(<String, Object?>{
        'candidates': <Object?>['not-a-map'],
      });
      expect(reply.blocked, isTrue);
      expect(reply.text, contains('पढ़ा नहीं जा सका'));
    });
  });

  group('GeminiService — असली request/response (MockClient)', () {
    test('URL, header aur body ka shape docs के मुताबिक', () async {
      final List<http.Request> sent = <http.Request>[];
      final GeminiService service = GeminiService(
        model: 'gemini-test-flash',
        apiKey: 'test-key-abcdefghijklmn',
        client: MockClient((http.Request request) async {
          sent.add(request);
          return http.Response(
            jsonEncode(_replyJson(text: 'जवाब तैयार है।')),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final AiReply reply = await service
          .startConversation(
            userText: 'आज कौन सा दिन है?',
            history: <ChatMessage>[_user('पिछला सवाल')],
            functionDeclarations: _declarations,
            extraContext: 'DEVICE CONTEXT: date=2026-10-13',
          )
          .respond();

      expect(reply.text, 'जवाब तैयार है।');
      expect(sent.single.method, 'POST');
      expect(sent.single.url.toString(),
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-test-flash:generateContent');
      expect(sent.single.headers['x-goog-api-key'], 'test-key-abcdefghijklmn');
      // key कभी URL में नहीं जाती
      expect(sent.single.url.query, isEmpty);

      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body['systemInstruction'], isNotNull);
      expect(((body['systemInstruction']! as Map<String, Object?>)['parts']! as List<Object?>).first,
          isA<Map<String, Object?>>());
      final String system = (((body['systemInstruction']! as Map<String, Object?>)['parts']!
              as List<Object?>)
          .first as Map<String, Object?>)['text'] as String;
      expect(system, contains('JARVIS'));
      expect(system, contains('DEVICE CONTEXT: date=2026-10-13'));

      final List<Object?> contents = body['contents']! as List<Object?>;
      expect(contents.length, 2, reason: 'history + current user turn');
      expect((contents[0]! as Map<String, Object?>)['role'], 'user');
      expect((contents[1]! as Map<String, Object?>)['role'], 'user');
      expect(body['generationConfig'], <String, Object?>{'maxOutputTokens': 700});
      // temperature/thinkingConfig जान-बूझकर नहीं भेजे जाते
      expect((body['generationConfig']! as Map<String, Object?>).containsKey('temperature'), isFalse);
      final List<Object?> tools = body['tools']! as List<Object?>;
      expect((tools.first! as Map<String, Object?>)['functionDeclarations'], isA<List<Object?>>());
      expect((body['toolConfig']! as Map<String, Object?>)['functionCallingConfig'],
          <String, Object?>{'mode': 'AUTO'});
      service.dispose();
    });

    test('tool round-trip: model turn एक ही, फिर functionResponse वाला user turn', () async {
      final List<Map<String, Object?>> sentContents = <Map<String, Object?>>[];
      final List<String> replies = <String>[
        jsonEncode(_replyJson(calls: <Map<String, Object?>>[
          <String, Object?>{
            'id': 'call_9',
            'name': 'get_current_time',
            'args': <String, Object?>{'info': 'both'},
          },
        ])),
        jsonEncode(_replyJson(text: 'रविवार, 11 अक्टूबर 2026।', finishReason: 'STOP')),
      ];
      final GeminiService service = GeminiService(
        model: 'gemini-test-flash',
        apiKey: 'test-key-abcdefghijklmn',
        client: MockClient((http.Request request) async {
          final Map<String, Object?> body =
              jsonDecode(request.body) as Map<String, Object?>;
          sentContents.add(<String, Object?>{'contents': body['contents']});
          return http.Response(replies.removeAt(0), 200);
        }),
      );

      final AiConversation conversation = service.startConversation(
        userText: 'तारीख़ बताओ',
        history: const <ChatMessage>[],
        functionDeclarations: _declarations,
      );

      final AiReply first = await conversation.respond();
      expect(first.wantsTools, isTrue);
      final ToolEcho echo = ToolEcho(
        call: first.toolCalls.single,
        result: ToolResult.ok('get_current_time',
            spokenText: 'रविवार, 11 अक्टूबर 2026',
            data: <String, Object?>{'weekday': 'Sunday'}),
      );
      final AiReply second = await conversation.submitToolResults(<ToolEcho>[echo]);
      expect(second.text, contains('रविवार'));

      // दूसरी request में history: user -> model(functionCall) -> user(functionResponse)
      final List<Object?> round2 =
          (sentContents[1]['contents']! as List<Object?>);
      expect(round2.length, 3);
      expect((round2[0]! as Map<String, Object?>)['role'], 'user');
      expect((round2[1]! as Map<String, Object?>)['role'], 'model');
      final List<Object?> modelParts =
          (round2[1]! as Map<String, Object?>)['parts']! as List<Object?>;
      expect(modelParts.single, isA<Map<String, Object?>>());
      expect((modelParts.first! as Map<String, Object?>)['functionCall'], isNotNull);
      // दो consecutive model turns = 400 — इसीलिए यहाँ user होना चाहिए
      expect((round2[2]! as Map<String, Object?>)['role'], 'user');
      final Map<String, Object?> fr = ((round2[2]! as Map<String, Object?>)['parts']!
              as List<Object?>)
          .first as Map<String, Object?>;
      final Map<String, Object?> response =
          fr['functionResponse']! as Map<String, Object?>;
      expect(response['name'], 'get_current_time');
      expect(response['id'], 'call_9');
      expect((response['response']! as Map<String, Object?>)['outcome'], 'success');
      expect((response['response']! as Map<String, Object?>)['data'],
          <String, Object?>{'weekday': 'Sunday'});
      service.dispose();
    });

    test('खाली जवाब पर contents में खाली model turn नहीं जुड़ता', () async {
      final List<int> sizes = <int>[];
      final GeminiService service = GeminiService(
        model: 'gemini-test-flash',
        apiKey: 'test-key-abcdefghijklmn',
        client: MockClient((http.Request request) async {
          final Map<String, Object?> body =
              jsonDecode(request.body) as Map<String, Object?>;
          sizes.add((body['contents']! as List<Object?>).length);
          return http.Response(jsonEncode(_replyJson()), 200);
        }),
      );
      final AiConversation conversation = service.startConversation(
        userText: 'हलो',
        history: const <ChatMessage>[],
        functionDeclarations: const <Map<String, Object?>>[],
      );
      expect((await conversation.respond()).text, isNull);
      expect((await conversation.respond()).text, isNull);
      expect(sizes, <int>[1, 1], reason: 'empty model turn भेजना 400 का सीधा रास्ता है');
      service.dispose();
    });

    test('429 (RPM, Retry-After: 2s) पर सिर्फ़ एक automatic retry, फिर सफल', () async {
      int calls = 0;
      final GeminiService service = GeminiService(
        model: 'gemini-test-flash',
        apiKey: 'test-key-abcdefghijklmn',
        client: MockClient((http.Request request) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'error': <String, Object?>{
                  'message': 'Resource has been exhausted (rate limit per-minute).',
                  'status': 'RESOURCE_EXHAUSTED',
                },
              }),
              429,
              headers: <String, String>{'retry-after': '1'},
            );
          }
          return http.Response(jsonEncode(_replyJson(text: 'अब चल गया')), 200);
        }),
      );
      final AiReply reply = await service
          .startConversation(
            userText: 'एक बार',
            history: const <ChatMessage>[],
            functionDeclarations: const <Map<String, Object?>>[],
          )
          .respond();
      expect(reply.text, 'अब चल गया');
      expect(calls, 2);
      service.dispose();
    });

    test('429 daily quota पर retry नहीं — सीधे honest error', () async {
      int calls = 0;
      final GeminiService service = GeminiService(
        model: 'gemini-test-flash',
        apiKey: 'test-key-abcdefghijklmn',
        client: MockClient((http.Request request) async {
          calls++;
          return http.Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{'message': 'You exceeded your current quota (daily).'},
            }),
            429,
          );
        }),
      );
      await expectLater(
        service
            .startConversation(
              userText: 'foo',
              history: const <ChatMessage>[],
              functionDeclarations: const <Map<String, Object?>>[],
            )
            .respond(),
        throwsA(isA<AiException>()
            .having((AiException e) => e.kind, 'kind', AiErrorKind.quotaExhausted)
            .having((AiException e) => e.canFallBackToLocal, 'fallback', isTrue)),
      );
      expect(calls, 1, reason: 'बिना Retry-After के दोबारा उधर नहीं भेजते');
      service.dispose();
    });

    test('galat key ka 401 UI tak AiException (Hindi) ke roop me aata है', () async {
      final GeminiService service = GeminiService(
        model: 'gemini-test-flash',
        apiKey: 'test-key-abcdefghijklmn',
        client: MockClient((http.Request request) async => http.Response(
            '{"error":{"message":"API key not valid. Please pass a valid API key.",'
            '"status":"UNAUTHENTICATED"}}',
            401)),
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
            .having((AiException e) => e.kind, 'kind', AiErrorKind.invalidKey)),
      );
      service.dispose();
    });

    test('timeout -> AiErrorKind.timeout (request टंगी रहे तो app नहीं टंगेगा)', () async {
      final GeminiService service = GeminiService(
        model: 'gemini-test-flash',
        apiKey: 'test-key-abcdefghijklmn',
        requestTimeout: const Duration(milliseconds: 30),
        client: MockClient((http.Request request) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        service
            .startConversation(
              userText: 'hi',
              history: const <ChatMessage>[],
              functionDeclarations: const <Map<String, Object?>>[],
            )
            .respond(),
        throwsA(isA<AiException>().having(
            (AiException e) => e.kind, 'kind', AiErrorKind.timeout)),
      );
      service.dispose();
    });

    test('200 par garbage body = badResponse, crash नहीं', () async {
      final GeminiService service = GeminiService(
        model: 'gemini-test-flash',
        apiKey: 'test-key-abcdefghijklmn',
        client: MockClient((http.Request request) async => http.Response('<html/>', 200)),
      );
      await expectLater(
        service
            .startConversation(
              userText: 'hi',
              history: const <ChatMessage>[],
              functionDeclarations: const <Map<String, Object?>>[],
            )
            .respond(),
        throwsA(isA<AiException>().having(
            (AiException e) => e.kind, 'kind', AiErrorKind.badResponse)),
      );
      service.dispose();
    });
  });

  group('healthCheck (Test API Connection button)', () {
    test('key न हो तो network कॉल ही नहीं — seedha Hindi सलाह', () async {
      final GeminiService service = GeminiService(model: 'gemini-test-flash');
      expect(service.isConfigured, isFalse);
      final AiHealth health = await service.healthCheck();
      expect(health.ok, isFalse);
      expect(health.message, contains('aistudio.google.com/apikey'));
      service.dispose();
    });

    test('सफल टेस्ट: latency + sample जवाब मिलता है, tools नहीं भेजे जाते', () async {
      http.Request? captured;
      final GeminiService service = GeminiService(
        model: 'gemini-test-flash',
        apiKey: 'test-key-abcdefghijklmn',
        client: MockClient((http.Request request) async {
          captured = request;
          return http.Response(jsonEncode(_replyJson(text: 'JARVIS ONLINE')), 200);
        }),
      );
      final AiHealth health = await service.healthCheck();
      expect(health.ok, isTrue);
      expect(health.message, contains('कनेक्शन काम कर रहा है'));
      expect(health.latencyMs, greaterThanOrEqualTo(0));
      expect(health.sample, 'JARVIS ONLINE');
      final Map<String, Object?> body = jsonDecode(captured!.body) as Map<String, Object?>;
      expect(body.containsKey('tools'), isFalse, reason: 'health check tool-free रहे');
      expect((body['generationConfig']! as Map<String, Object?>)['maxOutputTokens'], 24);
      service.dispose();
    });

    test('404 model: ok=false + model बदलने की सलाह (exception बाहर नहीं आती)', () async {
      final GeminiService service = GeminiService(
        model: 'gemini-nope',
        apiKey: 'test-key-abcdefghijklmn',
        client: MockClient((http.Request request) async => http.Response(
            '{"error":{"message":"models/gemini-nope is not found for API version v1beta"}}',
            404)),
      );
      final AiHealth health = await service.healthCheck();
      expect(health.ok, isFalse);
      expect(health.message, contains('मॉडल मिला नहीं'));
      service.dispose();
    });

    test('model चुप रहा (खाली parts) = ok false, फिर भी crash नहीं', () async {
      final GeminiService service = GeminiService(
        model: 'gemini-test-flash',
        apiKey: 'test-key-abcdefghijklmn',
        client: MockClient((http.Request request) async =>
            http.Response(jsonEncode(_replyJson()), 200)),
      );
      final AiHealth health = await service.healthCheck();
      expect(health.ok, isFalse);
      expect(health.message, contains('दूसरा model'));
      service.dispose();
    });
  });

  group('startConversation + labels', () {
    test('suggested models में default model मौजूद है, label में model दिखता है', () {
      final GeminiService service = GeminiService(
        model: GeminiService.defaultModel,
        apiKey: 'k',
      );
      expect(GeminiService.suggestedModels, contains(GeminiService.defaultModel));
      expect(service.label, 'Gemini · ${GeminiService.defaultModel}');
      expect(service.endpoint.toString(),
          'https://generativelanguage.googleapis.com/v1beta/models/${GeminiService.defaultModel}:generateContent');
      service.dispose();
    });

    test('custom baseUrl + trim (trailing slash वाला URL भी चले)', () {
      final GeminiService service = GeminiService(
        model: 'm',
        apiKey: ' k ',
        baseUrl: 'https://proxy.example.com/',
      );
      // trailing slash हटाना ज़रूरी है, वरना URL '//v1beta' बन कर 404 देता है
      expect(service.baseUrl, 'https://proxy.example.com');
      expect(service.baseUrl.endsWith('/'), isFalse);
      expect(service.endpoint.path, '/v1beta/models/m:generateContent');
      service.dispose();
    });

    test('debugRequestPreview: tool count aur history length, बिना network के', () async {
      final GeminiService service = GeminiService(
        model: 'gemini-test-flash',
        apiKey: 'test-key-abcdefghijklmn',
        client: MockClient((http.Request request) async => http.Response('{}', 200)),
      );
      final AiConversation conversation = service.startConversation(
        userText: 'hello',
        history: <ChatMessage>[_user('a'), _user('b')],
        functionDeclarations: _declarations,
      );
      final Map<String, Object?> preview = conversation.debugRequestPreview();
      expect(preview['model'], 'gemini-test-flash');
      expect(preview['contentsCount'], 3);
      expect(preview['tools'], 1);
      expect(preview['bodyKeys'], containsAll(<String>['contents', 'systemInstruction', 'generationConfig']));
      service.dispose();
    });
  });
}
