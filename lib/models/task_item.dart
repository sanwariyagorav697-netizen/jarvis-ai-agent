/// In-app task list (reminder tool ka local hissa — Android calendar se
/// abhi juda nahi hai; wo Phase 6 me aayega).
class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    this.done = false,
    required this.createdAt,
    this.completedAt,
  });

  final String id;
  final String title;
  final bool done;
  final DateTime createdAt;
  final DateTime? completedAt;

  TaskItem copyWith({String? title, bool? done, DateTime? completedAt}) =>
      TaskItem(
        id: id,
        title: title ?? this.title,
        done: done ?? this.done,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'done': done,
        'createdAt': createdAt.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };

  static TaskItem fromJson(Map<String, Object?> json) => TaskItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        done: json['done'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        completedAt: json['completedAt'] == null
            ? null
            : DateTime.tryParse(json['completedAt']! as String),
      );
}
