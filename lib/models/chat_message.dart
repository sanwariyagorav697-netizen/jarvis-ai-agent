/// Kaun bola — user, assistant, tool, ya system (error/info).
enum ChatRole { user, assistant, tool, system }

extension ChatRoleLabel on ChatRole {
  String get label => switch (this) {
        ChatRole.user => 'आप',
        ChatRole.assistant => 'JARVIS',
        ChatRole.tool => 'टूल',
        ChatRole.system => 'सिस्टम',
      };

  String get storageKey => name;

  static ChatRole fromStorageKey(String key) => ChatRole.values.firstWhere(
        (ChatRole r) => r.storageKey == key,
        orElse: () => ChatRole.system,
      );
}

/// Response ka source — UI me "device" vs "online provider" clearly dikhane ke
/// liye (requirement: user ko pata chale ki data kahan process hua).
enum AnswerSource { device, onlineModel, tool, localOnly }

extension AnswerSourceLabel on AnswerSource {
  String get label => switch (this) {
        AnswerSource.device => 'डिवाइस पर',
        AnswerSource.onlineModel => 'ऑनलाइन मॉडल से',
        AnswerSource.tool => 'टूल से',
        AnswerSource.localOnly => 'सिर्फ डिवाइस (AI अभी बंद)',
      };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.source,
    this.toolName,
    this.failed = false,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
  final AnswerSource? source;
  final String? toolName;

  /// true = tool fail hua / error message hai. UI laal border dikhata hai aur
  /// "success" wali koi animation nahi chalata.
  final bool failed;

  ChatMessage copyWith({String? text, bool? failed}) => ChatMessage(
        id: id,
        role: role,
        text: text ?? this.text,
        createdAt: createdAt,
        source: source,
        toolName: toolName,
        failed: failed ?? this.failed,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'role': role.storageKey,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'source': source?.name,
        'toolName': toolName,
        'failed': failed,
      };

  static ChatMessage fromJson(Map<String, Object?> json) {
    final Object? rawSource = json['source'];
    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: ChatRoleLabel.fromStorageKey(json['role'] as String? ?? 'system'),
      text: json['text'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      source: rawSource == null
          ? null
          : AnswerSource.values.firstWhere(
              (AnswerSource s) => s.name == rawSource,
              orElse: () => AnswerSource.localOnly,
            ),
      toolName: json['toolName'] as String?,
      failed: json['failed'] as bool? ?? false,
    );
  }
}
