import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jarvis_ai_agent/models/chat_message.dart';
import 'package:jarvis_ai_agent/services/ai/ai_service.dart';

ChatMessage _msg(ChatRole role, String text) => ChatMessage(
      id: '${role.name}-$text',
      role: role,
      text: text,
      createdAt: DateTime(2026, 10, 13),
    );

void main() {
  group('mapHttpFailure — हर status का साफ़ Hindi संदेश', () {
    test('400 + api_key_invalid = invalidKey (key दोबारा डालने को बोले)', () {
      final AiException e = mapHttpFailure(
        400,
        '{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.",'
            '"status":"INVALID_ARGUMENT"}}',
      );
      expect(e.kind, AiErrorKind.invalidKey);
      expect(e.message, contains('API key'));
      expect(e.retryable, isFalse);
      expect(e.canFallBackToLocal, isFalse);
    });

    test('400 + permission = permissionDenied (project me API enable नहीं)', () {
      final AiException e = mapHttpFailure(
        400,
        '{"error":{"message":"caller does not have permission to access'
            ' requester project","status":"FAILED_PRECONDITION"}}',
      );
      expect(e.kind, AiErrorKind.permissionDenied);
      expect(e.message, contains('enable'));
    });

    test('401/403 = invalidKey', () {
      expect(mapHttpFailure(401, '{"error":{"message":"unauthenticated"}}').kind,
          AiErrorKind.invalidKey);
      expect(mapHttpFailure(403, '{"error":{"message":"PERMISSION_DENIED"}}').kind,
          AiErrorKind.invalidKey);
    });

    test('404 = modelUnavailable, model बदलने का सुझाव', () {
      final AiException e = mapHttpFailure(
        404,
        '{"error":{"message":"models/gemini-9.9-ultra is not found for API version'
            ' v1beta, or is not supported for generateContent."}}',
      );
      expect(e.kind, AiErrorKind.modelUnavailable);
      expect(e.message, contains('मॉडल'));
      expect(e.canFallBackToLocal, isFalse);
    });

    test('429 प्रति-मिनट = rateLimited + retryAfter का संदेश', () {
      final AiException e = mapHttpFailure(
        429,
        '{"error":{"message":"Resource has been exhausted (e.g. check quota).",'
            '"status":"RESOURCE_EXHAUSTED","details":[{"reason":"RATE_LIMIT_EXCREASED",'
            '"metadata":{"sharding_key":"rpm","retry_delay":"60s"}}]}}',
        retryAfter: const Duration(seconds: 8),
      );
      expect(e.kind, AiErrorKind.rateLimited);
      expect(e.retryable, isTrue);
      expect(e.isQuota, isTrue);
      expect(e.message, contains('प्रति-मिनट'));
      expect(e.message, contains('8 सेकंड'));
    });

    test('429 दैनिक quota = quotaExhausted (आज और नहीं)', () {
      final AiException e = mapHttpFailure(
        429,
        '{"error":{"message":"You exceeded your current quota, please check your'
            ' plan and billing documents. daily quota per day exhausted"}}',
      );
      expect(e.kind, AiErrorKind.quotaExhausted);
      expect(e.retryable, isFalse);
      expect(e.canFallBackToLocal, isTrue, reason: 'net/tool काम चल सकता है');
      expect(e.message, contains('quota'));
    });

    test('500/502/503/504 = serverError (key में दोष नहीं)', () {
      for (final int status in <int>[500, 502, 503, 504]) {
        final AiException e = mapHttpFailure(status, '<html>bad gateway</html>');
        expect(e.kind, AiErrorKind.serverError, reason: 'status $status');
        expect(e.retryable, isTrue);
        expect(e.message, contains('सर्वर'));
      }
    });

    test('400 बिना detail के = badRequest, HTML page का raw body नहीं दिखता', () {
      final AiException e = mapHttpFailure(400, '<html><body>oops</body></html>');
      expect(e.kind, AiErrorKind.badRequest);
      expect(e.detail, contains('HTML error page'));
      expect(e.message, isNotEmpty);
      expect(e.toString(), startsWith('AiException(badRequest)'));
    });

    test('अनजान status (418) भी category + message देता है', () {
      final AiException e = mapHttpFailure(418, 'nope');
      expect(e.kind, AiErrorKind.badRequest);
      expect(e.message, contains('418'));
    });
  });

  group('error body helpers', () {
    test('JSON error.message निकलता है, 300 chars पर clip होता है', () {
      expect(
        summarizeErrorBody('{"error":{"message":"bad thing","status":"X"}}'),
        'bad thing',
      );
      final String long = jsonEncode(<String, Object?>{
        'error': <String, Object?>{'message': 'y' * 900},
      });
      expect(summarizeErrorBody(long).length, lessThanOrEqualTo(301));
      expect(summarizeErrorBody(''), isEmpty);
      expect(summarizeErrorBody('plain text'), 'plain text');
    });

    test('tryJson गंदे input पर null, कभी throw नहीं', () {
      expect(tryJson('{'), isNull);
      expect(tryJson('{"a":1}'), isA<Map<String, Object?>>());
    });

    test('parseRetryAfter seconds + clamp + कचरा', () {
      expect(parseRetryAfter('7'), const Duration(seconds: 7));
      expect(parseRetryAfter(' 900 '), const Duration(seconds: 120));
      expect(parseRetryAfter('0'), isNull);
      expect(parseRetryAfter('-5'), isNull);
      expect(parseRetryAfter('Fri, 13 Oct 2026'), isNull);
      expect(parseRetryAfter(null), isNull);
      expect(waitHint(const Duration(seconds: 45)), '45 सेकंड में फिर');
      expect(waitHint(const Duration(minutes: 2)), '2 मिनट में फिर');
      expect(waitHint(const Duration(seconds: 130)), '2 मिनट 10 सेकंड में फिर');
      expect(waitHint(null), 'थोड़ी देर में फिर');
    });

    test('kindFromStatus हर code को एक category देता है', () {
      expect(kindFromStatus(401), AiErrorKind.invalidKey);
      expect(kindFromStatus(403), AiErrorKind.invalidKey);
      expect(kindFromStatus(404), AiErrorKind.modelUnavailable);
      expect(kindFromStatus(429), AiErrorKind.rateLimited);
      expect(kindFromStatus(503), AiErrorKind.serverError);
      expect(kindFromStatus(400), AiErrorKind.badRequest);
    });

    test('blockedFromFeedback हिंदी में कारण बताता है', () {
      expect(blockedFromFeedback('SAFETY'), contains('सुरक्षा फ़िल्टर'));
      expect(blockedFromFeedback(null), contains('रोक दिया'));
    });
  });

  group('history + text safeguards', () {
    test('trimHistory सिर्फ user/assistant रखता है और last 10', () {
      final List<ChatMessage> mixed = <ChatMessage>[
        _msg(ChatRole.system, 'system prompt'),
        for (int i = 0; i < 8; i++) _msg(ChatRole.user, 'u$i'),
        for (int i = 0; i < 8; i++) _msg(ChatRole.assistant, 'a$i'),
        _msg(ChatRole.tool, 'tool noise'),
        _msg(ChatRole.user, '   '),
      ];
      final List<ChatMessage> trimmed = trimHistory(mixed);
      expect(trimmed.length, 10);
      expect(trimmed.first.text, 'u3');
      expect(trimmed.last.text, 'a7');
      expect(
        trimmed.every((ChatMessage m) =>
            m.role == ChatRole.user || m.role == ChatRole.assistant),
        isTrue,
      );
    });

    test('trimHistory छोटी history जैसी है वैसी रहती है', () {
      final List<ChatMessage> short = <ChatMessage>[_msg(ChatRole.user, 'ek')];
      expect(trimHistory(short), short);
      expect(trimHistory(<ChatMessage>[]), isEmpty);
    });

    test('clampUserText लंबा input काटता है (request size limit)', () {
      expect(clampUserText('छोटा सवाल'), 'छोटा सवाल');
      expect(clampUserText('क' * 5000).length, 2000);
    });

    test('maskSecret सिर्फ last 4 dikhaता है', () {
      expect(maskSecret(''), '');
      expect(maskSecret('abcd'), 'abcd');
      const String key = 'AIzaSyD-abcdefghij0123456789_KLMNOPQRSTU';
      expect(key.length, 40);
      expect(maskSecret(key), endsWith('RSTU'));
      expect(maskSecret(key), startsWith('•'));
      expect(maskSecret(key).length, 40, reason: 'लंबाई same रहे, असली हिस्सा सिर्फ़ 4 chars');
      expect(maskSecret(key), isNot(contains('AIzaSyD')));
    });
  });

  group('request helpers', () {
    test('jsonHeaders: key header में, URL में नहीं; bearer अलग provider के लिए', () {
      final Map<String, String> gemini = jsonHeaders(apiKey: 'AIza123');
      expect(gemini['x-goog-api-key'], 'AIza123');
      expect(gemini.containsKey('authorization'), isFalse);
      expect(gemini['content-type'], contains('application/json'));

      final Map<String, String> openai = jsonHeaders(bearerToken: 'gsk_abc');
      expect(openai['authorization'], 'Bearer gsk_abc');
      expect(openai.containsKey('x-goog-api-key'), isFalse);

      // खाली key = कोई auth header नहीं (crash/fake नहीं)
      expect(jsonHeaders(apiKey: '', bearerToken: null).length, 1);
    });

    test('requireJsonObject: 200 पर map, garbage पर badResponse error', () {
      expect(
        requireJsonObject(http.Response('{"a":1}', 200))['a'],
        1,
      );
      expect(
        () => requireJsonObject(http.Response('<html/>', 200)),
        throwsA(isA<AiException>().having(
            (AiException e) => e.kind, 'kind', AiErrorKind.badResponse)),
      );
      expect(
        () => requireJsonObject(http.Response('{}', 200)),
        throwsA(isA<AiException>()),
      );
    });

    test('mapTransportFailure: timeout/alag network error भी Hindi message देता है', () {
      expect(
        mapTransportFailure(TimeoutException('x')).kind,
        AiErrorKind.timeout,
      );
      expect(
        mapTransportFailure(http.ClientException('connection reset'))
            .message,
        contains('कनेक्शन'),
      );
      expect(
        mapTransportFailure(StateError('weird')).kind, AiErrorKind.network,
      );
    });
  });
}
