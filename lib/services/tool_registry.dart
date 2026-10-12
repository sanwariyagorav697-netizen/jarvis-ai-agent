import '../models/tool_result.dart';

/// Ek tool argument ka spec. Validation isi se hoti hai — model jo bhi JSON
/// bheje, wo yahan pass hue bina tool execute nahi hota.
class ToolParam {
  const ToolParam({
    required this.type,
    required this.description,
    this.required = true,
    this.enumValues,
    this.maxStringLength = 400,
  });

  /// 'string' | 'integer' | 'boolean' | 'number'
  final String type;
  final String description;
  final bool required;
  final List<String>? enumValues;
  final int maxStringLength;

  /// null = valid. Warna user-facing (Hindi) error message.
  String? validate(String key, Object? value) {
    if (value == null) {
      return required ? '`$key` zaroori hai.' : null;
    }
    switch (type) {
      case 'string':
        if (value is! String) return '`$key` string hona chahiye.';
        if (value.length > maxStringLength) {
          return '`$key` $maxStringLength character se lamba hai.';
        }
      case 'integer':
        if (value is! int) return '`$key` poora number (integer) hona chahiye.';
      case 'boolean':
        if (value is! bool) return '`$key` true/false hona chahiye.';
      case 'number':
        if (value is! num) return '`$key` number hona chahiye.';
      default:
        return '`$key` ka type (definition me) anjaan hai.';
    }
    final List<String>? allowed = enumValues;
    if (allowed != null && value is String && !allowed.contains(value)) {
      return '`$key` ka value "$value" supported nahi. Allowed: ${allowed.join(', ')}.';
    }
    return null;
  }

  Map<String, Object?> toJsonSchema() => <String, Object?>{
        'type': type,
        'description': description,
        if (enumValues != null) 'enum': enumValues,
      };
}

/// Sabhi tools ka base class.
abstract class JarvisTool {
  JarvisTool({
    required this.name,
    required this.description,
    this.params = const <String, ToolParam>{},
    this.requiresConfirmation = false,
    this.confirmationPrompt = '',
    this.needsNetwork = false,
  });

  final String name;
  final String description;
  final Map<String, ToolParam> params;

  /// Sensitive/irreversible kaam (call, SMS, device control) = true.
  final bool requiresConfirmation;
  final String confirmationPrompt;

  /// Sirf UI indicator ke liye (offline me in tools ko disable karne ke liye).
  final bool needsNetwork;

  /// Subclasses sirf yahan kaam karti hain. Return hamesha real outcome deta
  /// hai — kabhi bhi "ho gaya" nahi thropa jab tak Android ne haan na kahi ho.
  Future<ToolResult> run(ToolRequest request);

  /// Argument validation. null = sab theek.
  String? validateArguments(Map<String, Object?> arguments) {
    for (final MapEntry<String, ToolParam> e in params.entries) {
      if (e.value.required && !arguments.containsKey(e.key)) {
        return '`${e.key}` missing hai (${e.value.description}).';
      }
      final String? error = e.value.validate(e.key, arguments[e.key]);
      if (error != null) return error;
    }
    for (final String key in arguments.keys) {
      if (!params.containsKey(key)) {
        return '`$key` is tool ka supported argument nahi hai.';
      }
    }
    return null;
  }

  /// Phase 4 (AI tool-calling) me ye declarations model ko bheje jaate hain.
  Map<String, Object?> toFunctionDeclaration() => <String, Object?>{
        'name': name,
        'description': description,
        'parameters': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            for (final MapEntry<String, ToolParam> e in params.entries)
              e.key: e.value.toJsonSchema(),
          },
          if (params.values.any((ToolParam p) => p.required))
            'required': params.entries
                .where((MapEntry<String, ToolParam> e) => e.value.required)
                .map((MapEntry<String, ToolParam> e) => e.key)
                .toList(),
        },
      };
}

typedef ConfirmationHandler = Future<bool> Function(
    JarvisTool tool, ToolRequest request);

class ToolRegistry {
  ToolRegistry(Iterable<JarvisTool> tools) {
    for (final JarvisTool tool in tools) {
      register(tool);
    }
  }

  final Map<String, JarvisTool> _tools = <String, JarvisTool>{};

  void register(JarvisTool tool) {
    if (_tools.containsKey(tool.name)) {
      throw StateError('Duplicate tool name: ${tool.name}');
    }
    _tools[tool.name] = tool;
  }

  List<String> get names => _tools.keys.toList()..sort();

  bool has(String name) => _tools.containsKey(name);

  JarvisTool? find(String name) => _tools[name];

  List<Map<String, Object?>> functionDeclarations() => _tools.values
      .map((JarvisTool t) => t.toFunctionDeclaration())
      .toList(growable: false);

  /// Validate -> permission/confirmation -> execute. Har step ka real result.
  Future<ToolResult> execute(
    ToolRequest request, {
    ConfirmationHandler? confirm,
  }) async {
    final JarvisTool? tool = _tools[request.name.trim()];
    if (tool == null) {
      return ToolResult.unsupported(
        request.name,
        ' ye tool mere paas nahi hai. Available: ${names.join(', ')}.',
      );
    }

    final String? validationError = tool.validateArguments(request.arguments);
    if (validationError != null) {
      return ToolResult.fail(
        tool.name,
        'Argument check fail: $validationError',
        spokenText: 'Mujhe isme argument ki dikkat mili — $validationError',
      );
    }

    if (tool.requiresConfirmation && confirm != null) {
      final bool approved = await confirm(tool, request);
      if (!approved) {
        return ToolResult.denied(tool.name, 'आपने यह काम रोक दिया, मैंने कुछ नहीं किया।');
      }
    }

    try {
      return await tool.run(request);
    } on Object catch (error) {
      // Exception ko kabhi "success" me convert nahi karte.
      return ToolResult.fail(
        tool.name,
        'Tool execute karte waqt error: $error',
        spokenText: '${tool.name} chalate waqt dikkat aayi.',
      );
    }
  }
}
