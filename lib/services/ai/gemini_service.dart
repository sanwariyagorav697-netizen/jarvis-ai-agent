import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/chat_message.dart';
import 'ai_service.dart';
import 'jarvis_persona.dart';

/// Google Gemini (generativelanguage.googleapis.com) ka REST client — koi
/// Flutter plugin nahi, isliye version lock ka jhanjhat nahi aur error
/// handling poori hamare haath me rahti है।
///
/// Docs (2026): POST {base}/v1beta/models/{model}:generateContent, header
/// `x-goog-api-key`. Tools = `tools[].functionDeclarations`, model
/// `functionCall` parts lautata है, हम `functionResponse` bhejte हैं।
class GeminiService implements AiService {
  GeminiService({
    required this.model,
    String? apiKey,
    String baseUrl = defaultBaseUrl,
    this.requestTimeout = const Duration(seconds: 25),
    this.maxOutputTokens = 700,
    http.Client? client,
  })  : _apiKey = apiKey?.trim() ?? '',
        baseUrl = normalizeBaseUrl(baseUrl),
        _client = client ?? http.Client();

  static const String defaultBaseUrl =
      'https://generativelanguage.googleapis.com';

  /// Free tier par Pro models nahi hain (2026-04 se), इसलिए Flash-Lite default।
  static const String defaultModel = 'gemini-3.1-flash-lite';

  /// Settings me ye preset chips diye jaate हैं — user inme se chun sakta है
  /// ya khud type kar sakta है (Google naye model rename karta rehta है)।
  static const List<String> suggestedModels = <String>[
    'gemini-3.1-flash-lite',
    'gemini-3.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash',
  ];

  /// 429 par ek hi automatic chhota retry — sirf तब जब server खुद 12 सेकंड से
  /// कम बोले। Zyada ka wait user ko bata kar hi hotा है।
  static const int autoRetryMaxWaitSeconds = 12;

  final String model;
  final String baseUrl;
  final Duration requestTimeout;
  final int maxOutputTokens;
  final String _apiKey;
  final http.Client _client;

  @override
  String get label => 'Gemini · $model';

  @override
  bool get isConfigured => _apiKey.isNotEmpty;

  Uri get endpoint =>
      Uri.parse('$baseUrl/v1beta/models/$model:generateContent');

  Map<String, String> get headers => jsonHeaders(apiKey: _apiKey);

  @override
  AiConversation startConversation({
    required String userText,
    required List<ChatMessage> history,
    required List<Map<String, Object?>> functionDeclarations,
    String? extraContext,
  }) =>
      _GeminiConversation(
        service: this,
        userText: clampUserText(userText),
        history: trimHistory(history),
        declarations: functionDeclarations,
        extraContext: extraContext,
      );

  @override
  Future<AiHealth> healthCheck() async {
    if (!isConfigured) {
      return const AiHealth(
        ok: false,
        message:
            'API key सेटिंग्स में नहीं है। aistudio.google.com/apikey से key लीजिए और नीचे सेव कीजिए।',
        latencyMs: 0,
      );
    }
    final Stopwatch watch = Stopwatch()..start();
    final Map<String, Object?> body = <String, Object?>{
      'contents': <Object?>[
        <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{
              'text': 'Reply with exactly two words: JARVIS ONLINE',
            }
          ],
        }
      ],
      'generationConfig': <String, Object?>{'maxOutputTokens': 24},
    };
    try {
      final http.Response response = await postJson(
        _client,
        endpoint,
        body: body,
        headers: headers,
        timeout: requestTimeout,
      );
      watch.stop();
      if (response.statusCode != 200) {
        final AiException failure = mapHttpFailure(
          response.statusCode,
          responseText(response),
          retryAfter: parseRetryAfter(response.headers['retry-after']),
        );
        return AiHealth(
          ok: false,
          message: failure.message,
          latencyMs: watch.elapsedMilliseconds,
          sample: clip(failure.detail),
        );
      }
      final AiReply reply =
          GeminiParser.parseReply(requireJsonObject(response));
      final String text = (reply.text ?? '').trim();
      if (text.isEmpty) {
        return AiHealth(
          ok: false,
          message:
              'Key ने जवाब दे दिया पर मॉडल ने कुछ नहीं लिखा — ज़्यादातर case में यह model का block/safety है। दूसरा model चुनकर टेस्ट कीजिए।',
          latencyMs: watch.elapsedMilliseconds,
        );
      }
      return AiHealth(
        ok: true,
        message:
            'कनेक्शन काम कर रहा है (${watch.elapsedMilliseconds} ms में जवाब आया)।',
        latencyMs: watch.elapsedMilliseconds,
        sample: text,
      );
    } on AiException catch (failure) {
      watch.stop();
      return AiHealth(
        ok: false,
        message: failure.message,
        latencyMs: watch.elapsedMilliseconds,
        sample: clip(failure.detail),
      );
    } on Object catch (error) {
      watch.stop();
      final AiException failure = mapTransportFailure(error);
      return AiHealth(
        ok: false,
        message: failure.message,
        latencyMs: watch.elapsedMilliseconds,
      );
    }
  }

  @override
  void dispose() {
    _client.close();
  }
}

/// Gemini ka JSON -> [AiReply]. Public class hai taaki unit test network के
/// bina exact parsing check कर सके।
abstract final class GeminiParser {
  static AiReply parseReply(Map<String, Object?> json) {
    final List<Object?> candidates =
        (json['candidates'] as List<Object?>?) ?? const <Object?>[];
    if (candidates.isEmpty) {
      final Object? feedback = json['promptFeedback'];
      String? reason;
      if (feedback is Map<String, Object?>) {
        reason = feedback['blockReason'] as String?;
      }
      return AiReply(text: blockedFromFeedback(reason), blocked: true);
    }
    final Object? first = candidates.first;
    if (first is! Map<String, Object?>) {
      return AiReply(
        text: 'मॉडल का जवाब पढ़ा नहीं जा सका (अजीब response shape)।',
        blocked: true,
      );
    }

    final String finish = (first['finishReason'] as String? ?? '')
        .toLowerCase();
    if (finish == 'safety' ||
        finish == 'blocklist' ||
        finish == 'prohibited_content') {
      return AiReply(text: blockedFromFeedback(finish), blocked: true);
    }

    final Object? content = first['content'];
    final List<Object?> parts = content is Map<String, Object?>
        ? (content['parts'] as List<Object?>? ?? const <Object?>[])
        : const <Object?>[];

    final StringBuffer text = StringBuffer();
    final List<AiToolCall> calls = <AiToolCall>[];
    for (final Object? part in parts) {
      if (part is! Map<String, Object?>) {
        continue;
      }
      // Gemini 3 के "thinking" parts display-worthy nahi hote — ignore.
      if (part['thought'] == true) {
        continue;
      }
      final Object? chunk = part['text'];
      if (chunk is String) {
        text.write(chunk);
        continue;
      }
      final Object? call = part['functionCall'];
      if (call is Map<String, Object?>) {
        calls.add(AiToolCall(
          name: (call['name'] as String? ?? '').trim(),
          arguments: call['args'] is Map<String, Object?>
              ? Map<String, Object?>.from(call['args'] as Map<String, Object?>)
              : <String, Object?>{},
          callId: (part['functionCallId'] as String? ??
                  call['id'] as String? ??
                  '')
              .trim(),
        ));
      }
    }

    final String joined = text.toString().trim();
    return AiReply(
      text: joined.isEmpty ? null : joined,
      toolCalls: calls,
      truncated: finish == 'max_tokens',
    );
  }
}

class _GeminiConversation implements AiConversation {
  _GeminiConversation({
    required this.service,
    required String userText,
    required List<ChatMessage> history,
    required List<Map<String, Object?>> declarations,
    String? extraContext,
  }) : systemText = [
          kJarvisSystemPrompt,
          if (extraContext != null && extraContext.isNotEmpty) extraContext,
        ].join('\n\n'),
        contents = <Map<String, Object?>>[
          for (final ChatMessage message in history)
            if (message.role != ChatRole.system)
              <String, Object?>{
                'role': message.role == ChatRole.user ? 'user' : 'model',
                'parts': <Object?>[
                  <String, Object?>{'text': message.text},
                ],
              },
          <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{'text': userText},
            ],
          },
        ],
        declarations = List<Map<String, Object?>>.unmodifiable(declarations);

  /// Ek hi user-turn me zyada tool rounds na ho (cost + loop safety)।
  static const int _maxAutoRetries = 1;

  final GeminiService service;
  final String systemText;
  final List<Map<String, Object?>> declarations;
  final List<Map<String, Object?>> contents;

  int _retriesUsed = 0;

  @override
  Future<AiReply> respond() => _call();

  @override
  Future<AiReply> submitToolResults(List<ToolEcho> results) {
    contents.add(<String, Object?>{
      'role': 'user',
      'parts': <Object?>[
        for (final ToolEcho echo in results)
          <String, Object?>{
            'functionResponse': <String, Object?>{
              'name': echo.call.name,
              if (echo.call.callId.isNotEmpty) 'id': echo.call.callId,
              'response': echo.payload,
            },
          },
      ],
    });
    return _call();
  }

  Map<String, Object?> _requestBody() => <String, Object?>{
        'systemInstruction': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'text': systemText},
          ],
        },
        'contents': contents,
        'generationConfig': <String, Object?>{
          // temperature/thinkingConfig जान बूझकर नहीं भेजे जा रहे: Gemini 3 के
          // thinking models कुछ values पर 400 dete हैं। Default hi safe है।
          'maxOutputTokens': service.maxOutputTokens,
        },
        if (declarations.isNotEmpty)
          'tools': <Object?>[
            <String, Object?>{'functionDeclarations': declarations},
          ],
        if (declarations.isNotEmpty)
          'toolConfig': <String, Object?>{
            'functionCallingConfig': <String, Object?>{'mode': 'AUTO'},
          },
      };

  Future<http.Response> _send(Map<String, Object?> body) async {
    try {
      return await postJson(
        service._client,
        service.endpoint,
        body: body,
        headers: service.headers,
        timeout: service.requestTimeout,
      );
    } on Object catch (error) {
      // Transport failure = user-friendly Hindi; बाक़ी bug यैसे ही ऊपर जाता है।
      throw transportFailureFor(error) ?? error;
    }
  }

  Future<AiReply> _call() async {
    final http.Response response = await _send(_requestBody());

    if (response.statusCode != 200) {
      final AiException failure = mapHttpFailure(
        response.statusCode,
        responseText(response),
        retryAfter: parseRetryAfter(response.headers['retry-after']),
      );
      final int waitSeconds = failure.retryAfter?.inSeconds ?? 999;
      final bool worthOneRetry = _retriesUsed < _maxAutoRetries &&
          failure.kind == AiErrorKind.rateLimited &&
          waitSeconds <= GeminiService.autoRetryMaxWaitSeconds;
      if (worthOneRetry) {
        _retriesUsed++;
        await Future<void>.delayed(failure.retryAfter ?? const Duration(seconds: 3));
        return _call();
      }
      throw failure;
    }

    final AiReply reply = GeminiParser.parseReply(requireJsonObject(response));
    final List<Map<String, Object?>> modelParts = <Map<String, Object?>>[
      if (reply.text != null && reply.text!.isNotEmpty)
        <String, Object?>{'text': reply.text},
      for (final AiToolCall call in reply.toolCalls)
        <String, Object?>{
          'functionCall': <String, Object?>{
            'name': call.name,
            'args': call.arguments,
            if (call.callId.isNotEmpty) 'id': call.callId,
          },
        },
    ];
    // एक ही model turn — text और functionCall dono उसी me, वरना history
    // bi-chaine ho kar 400 देती है।
    if (modelParts.isNotEmpty) {
      contents.add(<String, Object?>{'role': 'model', 'parts': modelParts});
    }
    return reply;
  }

  @override
  Map<String, Object?> debugRequestPreview() => <String, Object?>{
        'model': service.model,
        'contentsCount': contents.length,
        'tools': declarations.length,
        'bodyKeys': _requestBody().keys.toList(),
        'systemInstructionChars': systemText.length,
        'requestJsonChars': jsonEncode(_requestBody()).length,
      };
}
