import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/chat_message.dart';
import 'ai_service.dart';
import 'jarvis_persona.dart';

/// Kisi bhi OpenAI-compatible `/chat/completions` endpoint ka client:
/// Groq (free tier), OpenRouter, ya Phase 4+ ka hamara FastAPI backend — sab
/// isi ek class se चलते हain, sirf baseUrl + model badलता है।
class OpenAiCompatService implements AiService {
  OpenAiCompatService({
    required this.model,
    String? apiKey,
    this.baseUrl = defaultBaseUrl,
    this.requestTimeout = const Duration(seconds: 25),
    this.maxOutputTokens = 700,
    http.Client? client,
  })  : _apiKey = apiKey?.trim() ?? '',
        _client = client ?? http.Client();

  /// Default Groq का OpenAI-compatible base URL (free tier, bina training)।
  static const String defaultBaseUrl = 'https://api.groq.com/openai/v1';

  /// OpenRouter के लिए: https://openrouter.ai/api/v1 (models `openai/gpt-oss-120b` जैसे)।
  static const String openRouterBaseUrl = 'https://openrouter.ai/api/v1';

  static const String defaultModel = 'llama-3.1-8b-instant';

  static const List<String> suggestedModels = <String>[
    'llama-3.1-8b-instant',
    'llama-3.3-70b-versatile',
    'openai/gpt-oss-120b',
  ];

  static const int autoRetryMaxWaitSeconds = 12;

  final String model;
  final String baseUrl;
  final Duration requestTimeout;
  final int maxOutputTokens;
  final String _apiKey;
  final http.Client _client;

  @override
  String get label => 'OpenAI-compatible · $model';

  @override
  bool get isConfigured => _apiKey.isNotEmpty;

  Uri get endpoint => Uri.parse('$baseUrl/chat/completions');

  Map<String, String> get headers => jsonHeaders(bearerToken: _apiKey);

  @override
  AiConversation startConversation({
    required String userText,
    required List<ChatMessage> history,
    required List<Map<String, Object?>> functionDeclarations,
    String? extraContext,
  }) =>
      _OpenAiConversation(
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
        message: 'इस provider के लिए API key सेटिंग्स में नहीं है।',
        latencyMs: 0,
      );
    }
    final Stopwatch watch = Stopwatch()..start();
    final Map<String, Object?> body = <String, Object?>{
      'model': model,
      'max_tokens': 24,
      'messages': <Object?>[
        <String, Object?>{
          'role': 'user',
          'content': 'Reply with exactly two words: JARVIS ONLINE',
        }
      ],
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
          response.body,
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
          OpenAiParser.parseReply(requireJsonObject(response));
      final String text = (reply.text ?? '').trim();
      if (text.isEmpty) {
        return AiHealth(
          ok: false,
          message: 'Endpoint ने JSON तो भेजा पर कोई text जवाब नहीं था। model name check कीजिए।',
          latencyMs: watch.elapsedMilliseconds,
        );
      }
      return AiHealth(
        ok: true,
        message: 'कनेक्शन काम कर रहा है (${watch.elapsedMilliseconds} ms में जवाब आया)।',
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

/// `/chat/completions` JSON -> [AiReply]।
abstract final class OpenAiParser {
  static AiReply parseReply(Map<String, Object?> json) {
    final List<Object?> choices =
        (json['choices'] as List<Object?>?) ?? const <Object?>[];
    if (choices.isEmpty) {
      final String detail = summarizeErrorBody(jsonEncode(json));
      return AiReply(
        text: detail.isEmpty
            ? 'मॉडल से कोई choices नहीं मिला। model name या safety setting check कीजिए।'
            : 'मॉडल से कोई choices नहीं मिला। API का कहना: $detail',
        blocked: true,
      );
    }
    final Object? first = choices.first;
    if (first is! Map<String, Object?>) {
      return const AiReply(
        text: 'मॉडल का जवाब पढ़ा नहीं जा सका (अजीब response shape)।',
        blocked: true,
      );
    }

    final String finish = (first['finish_reason'] as String? ?? '').toLowerCase();
    final Object? message = first['message'];
    if (message is! Map<String, Object?>) {
      return AiReply(
        text: finish == 'content_filter'
            ? blockedFromFeedback('safety')
            : 'मॉडल ने message field के बिना जवाब भेजा।',
        blocked: finish == 'content_filter',
      );
    }

    final Object? rawContent = message['content'];
    final String text = rawContent is String ? rawContent.trim() : '';
    // reasoning models कभी-kभี `reasoning_content` अलग field me देते हain — use नहीं करते।
    final List<AiToolCall> calls = <AiToolCall>[];
    final Object? toolCalls = message['tool_calls'];
    if (toolCalls is List<Object?>) {
      for (final Object? rawCall in toolCalls) {
        if (rawCall is! Map<String, Object?>) {
          continue;
        }
        final Object? fn = rawCall['function'];
        if (fn is! Map<String, Object?>) {
          continue;
        }
        calls.add(AiToolCall(
          name: (fn['name'] as String? ?? '').trim(),
          // OpenAI `arguments` ek JSON *string* hotी है; parse fail hone par
          // khaali args — tab ToolRegistry ki validation asli error batlाती
          // है, hum kabhi "chala gaya" nahi bolte।
          arguments: decodeArguments(fn['arguments']),
          callId: (rawCall['id'] as String? ?? '').trim(),
        ));
      }
    }

    return AiReply(
      text: text.isEmpty ? null : text,
      toolCalls: calls,
      truncated: finish == 'length',
    );
  }

  static Map<String, Object?> decodeArguments(Object? raw) {
    if (raw is Map<String, Object?>) {
      return Map<String, Object?>.from(raw);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final Object? decoded = tryJson(raw);
      if (decoded is Map<String, Object?>) {
        return Map<String, Object?>.from(decoded);
      }
    }
    return <String, Object?>{};
  }
}

class _OpenAiConversation implements AiConversation {
  _OpenAiConversation({
    required this.service,
    required String userText,
    required List<ChatMessage> history,
    required List<Map<String, Object?>> declarations,
    String? extraContext,
  })  : declarations = List<Map<String, Object?>>.unmodifiable(declarations),
        messages = <Map<String, Object?>>[
          <String, Object?>{
            'role': 'system',
            'content': <String>[
              kJarvisSystemPrompt,
              if (extraContext != null && extraContext.isNotEmpty) extraContext,
            ].join('\n\n'),
          },
          for (final ChatMessage message in history)
            if (message.role == ChatRole.user || message.role == ChatRole.assistant)
              <String, Object?>{
                'role': message.role == ChatRole.user ? 'user' : 'assistant',
                'content': message.text,
              },
          <String, Object?>{'role': 'user', 'content': userText},
        ];

  static const int _maxAutoRetries = 1;

  final OpenAiCompatService service;
  final List<Map<String, Object?>> declarations;
  final List<Map<String, Object?>> messages;

  int _retriesUsed = 0;

  @override
  Future<AiReply> respond() => _call();

  @override
  Future<AiReply> submitToolResults(List<ToolEcho> results) {
    for (final ToolEcho echo in results) {
      messages.add(<String, Object?>{
        'role': 'tool',
        'tool_call_id': echo.call.callId.isEmpty ? echo.call.name : echo.call.callId,
        'name': echo.call.name,
        // OpenAI ko tool ka jawab string me chahiye (content field)।
        'content': jsonEncode(echo.payload),
      });
    }
    return _call();
  }

  Map<String, Object?> _requestBody() => <String, Object?>{
        'model': service.model,
        'messages': messages,
        // temperature जान-बूझकर नहीं भेजते: कुछ hosted endpoints allowed range
        // से बाहर की value पर 400 dete हain।
        'max_tokens': service.maxOutputTokens,
        if (declarations.isNotEmpty)
          'tools': <Object?>[
            for (final Map<String, Object?> decl in declarations)
              <String, Object?>{'type': 'function', 'function': decl},
          ],
        if (declarations.isNotEmpty) 'tool_choice': 'auto',
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
      throw mapTransportFailure(error);
    }
  }

  Future<AiReply> _call() async {
    final http.Response response = await _send(_requestBody());

    if (response.statusCode != 200) {
      final AiException failure = mapHttpFailure(
        response.statusCode,
        response.body,
        retryAfter: parseRetryAfter(response.headers['retry-after']),
      );
      final int waitSeconds = failure.retryAfter?.inSeconds ?? 999;
      final bool worthOneRetry = _retriesUsed < _maxAutoRetries &&
          failure.kind == AiErrorKind.rateLimited &&
          waitSeconds <= OpenAiCompatService.autoRetryMaxWaitSeconds;
      if (worthOneRetry) {
        _retriesUsed++;
        await Future<void>.delayed(
            failure.retryAfter ?? const Duration(seconds: 3));
        return _call();
      }
      throw failure;
    }

    final AiReply reply = OpenAiParser.parseReply(requireJsonObject(response));
    final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[
      for (final AiToolCall call in reply.toolCalls)
        <String, Object?>{
          'id': call.callId.isEmpty ? call.name : call.callId,
          'type': 'function',
          'function': <String, Object?>{
            'name': call.name,
            'arguments': jsonEncode(call.arguments),
          },
        },
    ];
    final String? content = reply.text;
    if (content == null && toolCalls.isEmpty) {
      return reply;
    }
    // assistant turn ek hi baar, text + tool_calls dono ke saath।
    messages.add(<String, Object?>{
      'role': 'assistant',
      'content': content ?? '',
      if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
    });
    return reply;
  }

  @override
  Map<String, Object?> debugRequestPreview() => <String, Object?>{
        'model': service.model,
        'messagesCount': messages.length,
        'roles': messages
            .map((Map<String, Object?> m) => m['role'].toString())
            .toList(growable: false),
        'tools': declarations.length,
        'bodyKeys': _requestBody().keys.toList(),
        'requestJsonChars': jsonEncode(_requestBody()).length,
      };
}
