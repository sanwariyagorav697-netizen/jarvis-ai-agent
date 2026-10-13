import '../models/task_item.dart';
import '../models/tool_result.dart';
import '../services/memory_service.dart';
import '../services/tool_registry.dart';

/// In-app task list tools. Ye sirf app ke apne storage me likhte hain —
/// Android ka reminder/calendar abhi touch nahi karte (Phase 6), isliye koi
/// permission nahi chahiye aur ye offline bhi chalta hai.
class TaskToolBase {
  TaskToolBase(this.memory);

  final MemoryService memory;

  static String summarize(List<TaskItem> tasks) {
    if (tasks.isEmpty) return 'कोई काम लिस्ट में नहीं है।';
    final List<TaskItem> open =
        tasks.where((TaskItem t) => !t.done).toList(growable: false);
    final String lines = open
        .take(5)
        .toList(growable: false)
        .asMap()
        .entries
        .map((MapEntry<int, TaskItem> e) => '${e.key + 1}. ${e.value.title}')
        .join(', ');
    if (lines.isEmpty) {
      return 'सब ${tasks.length} काम पूरे हो चुके हैं।';
    }
    return '${open.length} काम बाकी हैं: $lines';
  }
}

class AddTaskTool extends JarvisTool {
  AddTaskTool(this._memory)
      : super(
          name: 'add_task',
          description: 'In-app task list me ek nayi entry jodta hai.',
          params: const <String, ToolParam>{
            'title': ToolParam(
              type: 'string',
              description: 'Task ka text, e.g. "दवा लेना".',
              maxStringLength: 160,
            ),
          },
        );

  final MemoryService _memory;

  @override
  Future<ToolResult> run(ToolRequest request) async {
    final String title = (request['title'] as String? ?? '').trim();
    if (title.isEmpty) {
      return ToolResult.fail('add_task', 'Task ka title खाली नहीं हो सकता।');
    }
    final List<TaskItem> tasks = await _memory.loadTasks();
    final TaskItem item = TaskItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      createdAt: DateTime.now(),
    );
    await _memory.replaceTasks(<TaskItem>[...tasks, item]);
    return ToolResult.ok(
      'add_task',
      spokenText: 'जोड़ दिया: $title',
      data: <String, Object?>{'total': tasks.length + 1, 'id': item.id},
    );
  }
}

class ListTasksTool extends JarvisTool {
  ListTasksTool(this._memory)
      : super(
          name: 'list_tasks',
          description: 'In-app task list padhta hai (pending tasks batata hai).',
        );

  final MemoryService _memory;

  @override
  Future<ToolResult> run(ToolRequest request) async {
    final List<TaskItem> tasks = await _memory.loadTasks();
    final List<TaskItem> open =
        tasks.where((TaskItem t) => !t.done).toList(growable: false);
    return ToolResult.ok(
      'list_tasks',
      spokenText: TaskToolBase.summarize(tasks),
      data: <String, Object?>{
        'total': tasks.length,
        'open': open.length,
        'titles': open.map((TaskItem t) => t.title).take(10).toList(),
      },
    );
  }
}

class CompleteTaskTool extends JarvisTool {
  CompleteTaskTool(this._memory)
      : super(
          name: 'complete_task',
          description:
              'Task को done mark करता है। दिए गए text से मेल खाता खुला task ढूँढता है।',
          params: const <String, ToolParam>{
            'match': ToolParam(
              type: 'string',
              description: 'Task के title का कोई हिस्सा।',
              maxStringLength: 160,
            ),
          },
        );

  final MemoryService _memory;

  @override
  Future<ToolResult> run(ToolRequest request) async {
    final String match = (request['match'] as String? ?? '').trim().toLowerCase();
    final List<TaskItem> tasks = await _memory.loadTasks();
    final int index = tasks.indexWhere(
        (TaskItem t) => !t.done && t.title.toLowerCase().contains(match));
    if (index < 0) {
      return ToolResult.fail('complete_task',
          'इस मेल खाता हुआ कोई खुला task नहीं मिला: "$match".');
    }
    final TaskItem updated =
        tasks[index].copyWith(done: true, completedAt: DateTime.now());
    await _memory.replaceTasks(<TaskItem>[
      ...tasks.sublist(0, index),
      updated,
      ...tasks.sublist(index + 1),
    ]);
    return ToolResult.ok(
      'complete_task',
      spokenText: 'पूरा हुआ: ${updated.title}',
      data: <String, Object?>{'id': updated.id},
    );
  }
}
