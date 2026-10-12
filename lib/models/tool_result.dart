/// Ek tool call ka input (model ya local router se aata hai) + uska result.
///
/// Zaroori design rule: model ko kabhi bhi shell/arbitrary code execute nahi
/// karne diya jata. Sirf {name, arguments} aata hai, aur registry hi decide
/// karti hai ki kuch chalega ya nahi.
class ToolRequest {
  const ToolRequest({required this.name, required this.arguments});

  final String name;
  final Map<String, Object?> arguments;

  Object? operator [](String key) => arguments[key];

  @override
  String toString() => '$name(${arguments.keys.join(', ')})';
}

enum ToolOutcome {
  /// tool chala aur usne khud ko succeed bataya (real Android result se verified)
  success,

  /// tool chala par fail hua — UI sach me "fail" dikhata hai
  failure,

  /// user ne confirmation reject ki, ya Android permission nahi di
  denied,

  /// is device/OS version par supported hi nahi
  unsupported,

  /// abhi implement hi nahi hua (kabhi bhi "success" ka fake nahi)
  notImplemented,
}

class ToolResult {
  const ToolResult({
    required this.outcome,
    required this.toolName,
    this.spokenText = '',
    this.data = const <String, Object?>{},
    this.errorMessage,
  });

  factory ToolResult.ok(String toolName,
          {required String spokenText,
          Map<String, Object?> data = const <String, Object?>{}}) =>
      ToolResult(
        outcome: ToolOutcome.success,
        toolName: toolName,
        spokenText: spokenText,
        data: data,
      );

  factory ToolResult.fail(String toolName, String errorMessage,
          {String spokenText = ''}) =>
      ToolResult(
        outcome: ToolOutcome.failure,
        toolName: toolName,
        errorMessage: errorMessage,
        spokenText: spokenText.isEmpty ? errorMessage : spokenText,
      );

  factory ToolResult.denied(String toolName, String why) => ToolResult(
        outcome: ToolOutcome.denied,
        toolName: toolName,
        errorMessage: why,
        spokenText: why,
      );

  factory ToolResult.unsupported(String toolName, String why) => ToolResult(
        outcome: ToolOutcome.unsupported,
        toolName: toolName,
        errorMessage: why,
        spokenText: why,
      );

  factory ToolResult.notImplemented(String toolName, String why) => ToolResult(
        outcome: ToolOutcome.notImplemented,
        toolName: toolName,
        errorMessage: why,
        spokenText: why,
      );

  final ToolOutcome outcome;
  final String toolName;

  /// Jo TTS se bola jayega. Empty hone par UI sirf status chip dikhata hai.
  final String spokenText;

  /// Structured data (model ko wapas bheja jaata hai, UI me nahi thropa).
  final Map<String, Object?> data;

  final String? errorMessage;

  bool get isSuccess => outcome == ToolOutcome.success;

  Map<String, Object?> toJson() => <String, Object?>{
        'tool': toolName,
        'outcome': outcome.name,
        'data': data,
        if (errorMessage != null) 'error': errorMessage,
      };
}
