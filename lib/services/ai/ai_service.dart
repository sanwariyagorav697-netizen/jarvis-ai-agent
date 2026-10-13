import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/chat_message.dart';
import '../../models/tool_result.dart';

/// AI provider ke saath hone wali har dikkat ka ek stable type. Provider ke
/// HTTP status codes ko yahi map kiya jata hai, taaki UI har baar status code
/// decode na kare.
enum AiErrorKind {
  notConfigured,
  invalidKey,
  permissionDenied,
  quotaExhausted,
  rateLimited,
  modelUnavailable,
  badRequest,
  serverError,
  network,
  timeout,
  badResponse,
  blocked,
}

class AiException implements Exception {
  const AiException({
    required this.kind,
    required this.message,
    this.retryAfter,
    this.detail = '',
  });

  final AiErrorKind kind;

  /// User ko dikhane wali Hindi line — hamesha banti है, कभी खाली नहीं।
  final String message;

  /// Server ne 'Retry-After' bheja ho to wo duration।
  final Duration? retryAfter;

  /// Provider ka kachra message — sirf debug/statusDetail ke liye, chat me nahi।
  final String detail;

  bool get isQuota =>
      kind == AiErrorKind.quotaExhausted || kind == AiErrorKind.rateLimited;

  /// Wahi request thoda ruk kar dohra ja sakta है।
  bool get retryable =>
      kind == AiErrorKind.rateLimited ||
      kind == AiErrorKind.serverError ||
      kind == AiErrorKind.network ||
      kind == AiErrorKind.timeout;

  /// Aisi failure jab device-only jawab imandari se "यह अभी नहीं हो सका"
  /// dikhane लायक है (fake success कभी नहीं)।
  bool get canFallBackToLocal =>
      kind == AiErrorKind.network ||
      kind == AiErrorKind.timeout ||
      kind == AiErrorKind.serverError ||
      kind == AiErrorKind.rateLimited ||
      kind == AiErrorKind.quotaExhausted ||
      kind == AiErrorKind.notConfigured ||
      kind == AiErrorKind.blocked;

  @override
  String toString() => 'AiException(${kind.name}): $message';
}

/// Model ne jo tool chalane ko kaha. Ye sirf *suggest* karta है — chalane का
/// ekmatra adhikar ToolRegistry के पास है (validation + confirmation)।
class AiToolCall {
  const AiToolCall({
    required this.name,
    required this.arguments,
    this.callId = '',
  });

  final String name;
  final Map<String, Object?> arguments;

  /// Gemini 3 aur OpenAI dono id dete हain; jawab me wapas lautाना zaroori है।
  final String callId;

  @override
  String toString() => '$name(${arguments.keys.join(', ')})';
}

/// Ek model turn का parsed jawab।
class AiReply {
  const AiReply({
    this.text,
    this.toolCalls = const <AiToolCall>[],
    this.truncated = false,
    this.blocked = false,
  });

  final String? text;
  final List<AiToolCall> toolCalls;

  /// true = maxOutputTokens पर jawab kat gaya (UI "adhूra" note lagata है)।
  final bool truncated;

  /// true = safety filter ने jawab rok diya।
  final bool blocked;

  bool get wantsTools => toolCalls.isNotEmpty;
}

/// Tool का asli result, model को wapas bhejne के लिए. Ek hi object से
/// Gemini का functionResponse और OpenAI का role:tool dono bante हain।
class ToolEcho {
  const ToolEcho({required this.call, required this.result});

  final AiToolCall call;
  final ToolResult result;

  Map<String, Object?> get payload => result.toJson();

  /// Chat me dikhane वाली एक line — हमेशा registry के real result से।
  String get displayLine => result.isSuccess
      ? '${result.toolName} ✓'
      : '${result.toolName} ✗ ${result.errorMessage ?? result.outcome.name}';
}

/// "Test API Connection" button का natija।
class AiHealth {
  const AiHealth({
    required this.ok,
    required this.message,
    required this.latencyMs,
    this.sample = '',
  });

  final bool ok;
  final String message;
  final int latencyMs;
  final String sample;
}

/// Ek user-turn की multi-round tool conversation. Provider-specific JSON isi
/// के अंदर rehta है — agent को sirf [respond] aur [submitToolResults] dikhte हain।
abstract class AiConversation {
  Future<AiReply> respond();

  Future<AiReply> submitToolResults(List<ToolEcho> results);

  /// Kitne tool rounds allowed (infinite loop से bachne के लिए)।
  static const int maxToolRounds = 3;

  /// Test/diagnostics ke liye: is turn ka request shape, bina network bhेजे।
  /// Isme koi secret nahi hotा (key headers me rehti है, body me नहीं)।
  Map<String, Object?> debugRequestPreview();
}

abstract class AiService {
  /// e.g. "Gemini · gemini-3.1-flash-lite"
  String get label;

  bool get isConfigured;

  /// [history] me current user text shaamil nahi hotा।
  /// [extraContext] = system instruction के साथ jaane वाला bharosemand device
  /// context (date/time) — model inhe guess na kare।
  AiConversation startConversation({
    required String userText,
    required List<ChatMessage> history,
    required List<Map<String, Object?>> functionDeclarations,
    String? extraContext,
  });

  /// Chhota, tool-free request — sirf yeh check karne के लिए कि key + model
  /// सच me काम कर रहे हain या नहीं।
  Future<AiHealth> healthCheck();

  void dispose();
}

// ---------------------------------------------------------------- shared utils

/// Status code का default category (body से kuch na मिले तो यही इस्तेमाल होता है)।
AiErrorKind kindFromStatus(int status) {
  if (status == 401 || status == 403) {
    return AiErrorKind.invalidKey;
  }
  if (status == 404) {
    return AiErrorKind.modelUnavailable;
  }
  if (status == 429) {
    return AiErrorKind.rateLimited;
  }
  if (status >= 500) {
    return AiErrorKind.serverError;
  }
  return AiErrorKind.badRequest;
}

/// HTTP error को readable Hindi message में बदलता है। Dono providers isi को
/// use करते हain, ताaki हर provider पर behavior एक जैसा रहे।
AiException mapHttpFailure(int status, String body, {Duration? retryAfter}) {
  final String detail = summarizeErrorBody(body);
  final String lower = detail.toLowerCase();

  AiException wrap(AiErrorKind kind, String message) => AiException(
        kind: kind,
        message: message,
        retryAfter: retryAfter,
        detail: detail,
      );

  if (status == 400 || status == 422) {
    if (lower.contains('api_key_invalid') ||
        lower.contains('api key not valid') ||
        lower.contains('invalid authentication')) {
      return wrap(AiErrorKind.invalidKey,
          'आपकी API key गलत या रद्द हो गई है। aistudio.google.com/apikey से नई key बनाकर Settings में डालिए।');
    }
    if (lower.contains('no permission') || lower.contains('permission')) {
      return wrap(AiErrorKind.permissionDenied,
          'इस key वाले project पर Gemini API चालू नहीं है। Google Cloud Console में "Generative Language API" enable कीजिए।');
    }
    if (lower.contains('not found') || lower.contains('unsupported')) {
      return wrap(AiErrorKind.modelUnavailable,
          'यह मॉडल आपकी key पर उपलब्ध नहीं है। Settings में दूसरा मॉडल चुनिए।');
    }
    return wrap(AiErrorKind.badRequest,
        'Request समझ में नहीं आया (model या arguments में समस्या)। दोबारा पूछिए, नतीजा न हो तो Settings में मॉडल बदलिए।');
  }
  if (status == 401 || status == 403) {
    return wrap(AiErrorKind.invalidKey,
        'API key से अनुमति नहीं मिली। key पूरा copy हुआ है और उस project पर Gemini API चालू है — यह देखिए।');
  }
  if (status == 404) {
    return wrap(AiErrorKind.modelUnavailable,
        'मॉडल मिला नहीं। Settings में model name ठीक कीजिए (जैसे gemini-3.1-flash-lite)।');
  }
  if (status == 429) {
    // 429 दो अलग बातें हो सकती हैं: प्रति-मिनट सीमा (थोड़ा रुक कर चलेगा) और
    // दैनिक quota (आज के लिए खत्म) — इसलिए संदेश भी अलग है।
    final bool minuteLimited = lower.contains('per-minute') ||
        lower.contains('per minute') ||
        lower.contains('rpm') ||
        lower.contains('rate limit');
    final bool daily = !minuteLimited &&
        (lower.contains('quota') ||
            lower.contains('per day') ||
            lower.contains('per-day') ||
            lower.contains('resource_exhausted'));
    if (daily) {
      return wrap(AiErrorKind.quotaExhausted,
          'आज का फ्री quota खत्म हो गया है। Google इसे आधी रात (Pacific time) के बाद फिर देता है — तब तक मैं डिवाइस के अपने टूल खुद चला सकता हूँ।');
    }
    return wrap(
      AiErrorKind.rateLimited,
      'फ्री tier की प्रति-मिनट सीमा भर गई है। ${waitHint(retryAfter)} कोशिश कीजिए।',
    );
  }
  if (status >= 500) {
    return wrap(AiErrorKind.serverError,
        '$status — सर्वर की तरफ से दिक्कत है (आपकी key में नहीं)। ${waitHint(retryAfter)} कोशिश कीजिए।');
  }
  return wrap(kindFromStatus(status), 'API ने error $status लौटाया। ${waitHint(retryAfter)} कोशिश कीजिए।');
}

/// 'Retry-After' से हिन्दी "कब फिर करें" संकेत।
String waitHint(Duration? retryAfter) {
  if (retryAfter == null) {
    return 'थोड़ी देर में फिर';
  }
  final int seconds = retryAfter.inSeconds;
  if (seconds < 60) {
    return '$seconds सेकंड में फिर';
  }
  final int minutes = seconds ~/ 60;
  final int rest = seconds % 60;
  return rest == 0
      ? '$minutes मिनट में फिर'
      : '$minutes मिनट $rest सेकंड में फिर';
}

/// Har network failure को एक ही shape में (timeout/offline/DNS)।
AiException mapTransportFailure(Object error) {
  if (error is TimeoutException) {
    return const AiException(
      kind: AiErrorKind.timeout,
      message:
          'समय पर जवाब नहीं आया (25 सेकंड)। नेटवर्क धीमा लग रहा है — दोबारा पूछिए।',
    );
  }
  if (error is http.ClientException) {
    return AiException(
      kind: AiErrorKind.network,
      message: 'API से कनेक्शन नहीं बन पाया। Wi-Fi/मोबाइल डेटा चालू करके दोबारा पूछिए।',
      detail: error.message,
    );
  }
  return AiException(
    kind: AiErrorKind.network,
    message: 'नेटवर्क पर कुछ दिक्कत आई। इंटरनेट देखकर दोबारा पूछिए।',
    detail: '$error',
  );
}

/// Provider का error body (कभी-कभी 2 KB HTML) छोटा + पढ़ने लायक बनाता है।
String summarizeErrorBody(String body) {
  final String trimmed = body.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.startsWith('{')) {
    final Object? decoded = tryJson(trimmed);
    if (decoded is Map<String, Object?>) {
      for (final String key in <String>['error', 'message']) {
        final Object? value = decoded[key];
        if (value is Map<String, Object?>) {
          final Object? nested = value['message'];
          if (nested is String && nested.isNotEmpty) {
            return clip(nested);
          }
        }
        if (value is String && value.isNotEmpty) {
          return clip(value);
        }
      }
    }
    return clip(trimmed);
  }
  if (trimmed.startsWith('<')) {
    return 'सर्वर ने HTML error page भेजा (विवरण सुरक्षा के लिए नहीं दिखाया गया)';
  }
  return clip(trimmed);
}

Object? tryJson(String source) {
  try {
    return jsonDecode(source);
  } on FormatException {
    return null;
  }
}

String clip(String value) =>
    value.length <= 300 ? value : '${value.substring(0, 300)}…';

/// 'Retry-After' header (seconds) से Duration; 120s से ऊपर clamp (app freeze
/// से bachने के लिए कभी बड़ा timer nahi banate)।
Duration? parseRetryAfter(String? raw) {
  final String? value = raw?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  final int? seconds = int.tryParse(value);
  if (seconds == null || seconds <= 0) {
    return null;
  }
  return Duration(seconds: seconds > 120 ? 120 : seconds);
}

/// Gemini safetyFeedback / moderation जैसे block reason का साफ़ संदेश।
String blockedFromFeedback(String? reason) {
  final String key = (reason ?? '').toLowerCase();
  final String kya = switch (key) {
    'blocked' || 'safety' || 'blocklist' || 'prohibited_content' =>
      'सुरक्षा फ़िल्टर',
    'other' || 'unspecified' || 'recitation' => 'फ़िल्टर',
    _ => 'API ने',
  };
  return '$kya ने यह जवाब रोक दिया। शब्द बदलकर दोबारा पूछिए।';
}

/// 200 + JSON की गारंटी; वरना [AiErrorKind.badResponse]।
Map<String, Object?> requireJsonObject(http.Response response) {
  final Object? decoded = tryJson(response.body.trim());
  if (decoded is Map<String, Object?> && decoded.isNotEmpty) {
    return decoded;
  }
  throw AiException(
    kind: AiErrorKind.badResponse,
    message: 'API का जवाब पढ़ा नहीं जा सका (JSON नहीं मिला)। दोबारा पूछिए।',
    detail: clip(response.body),
  );
}

/// Chat history का पिछला हिस्सा, model के लिए (token बचत + पुरानी बेमतलब
/// बातें भेजने से बचाव)।
List<ChatMessage> trimHistory(List<ChatMessage> history,
    {int maxMessages = 10}) {
  final List<ChatMessage> usable = history
      .where((ChatMessage m) =>
          (m.role == ChatRole.user || m.role == ChatRole.assistant) &&
          m.text.trim().isNotEmpty)
      .toList(growable: false);
  if (usable.length <= maxMessages) {
    return usable;
  }
  return usable.sublist(usable.length - maxMessages);
}

/// User text की length cap (request size + free-tier tokens बचाने के लिए)।
String clampUserText(String text) =>
    text.length <= 2000 ? text : text.substring(0, 2000);

/// Secret दिखाने के लिए: सिर्फ़ last 4 characters।
String maskSecret(String secret) {
  if (secret.isEmpty) {
    return '';
  }
  final int visible = secret.length <= 4 ? secret.length : 4;
  return '${'•' * (secret.length - visible)}${secret.substring(secret.length - visible)}';
}

/// Gemini/OpenAI-compatible dono के headers एक ही जगह से — key कभी URL में
/// query parameter के रूप में नहीं जाती (logs/referrer me leak हो सकती है)।
Map<String, String> jsonHeaders({String? apiKey, String? bearerToken}) {
  return <String, String>{
    'content-type': 'application/json; charset=utf-8',
    if (apiKey != null && apiKey.isNotEmpty) 'x-goog-api-key': apiKey,
    if (bearerToken != null && bearerToken.isNotEmpty)
      'authorization': 'Bearer $bearerToken',
  };
}

/// POST + timeout एक ही जगह से (200 आने पर भी timeout लागू रहे इसलिए यहीं)।
Future<http.Response> postJson(
  http.Client client,
  Uri url, {
  required Map<String, Object?> body,
  required Map<String, String> headers,
  required Duration timeout,
}) {
  return client
      .post(url, headers: headers, body: jsonEncode(body))
      .timeout<http.Response>(timeout, onTimeout: () {
    throw TimeoutException('AI request timeout', timeout);
  });
}
