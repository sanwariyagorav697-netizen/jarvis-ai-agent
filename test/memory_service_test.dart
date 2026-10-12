import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_ai_agent/models/chat_message.dart';
import 'package:jarvis_ai_agent/models/task_item.dart';
import 'package:jarvis_ai_agent/services/memory_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('history serialisation', () {
    test('round-trips every field', () {
      final ChatMessage m = ChatMessage(
        id: 'a1',
        role: ChatRole.assistant,
        text: 'शाम 7 बजकर 42 मिनट',
        createdAt: DateTime(2026, 10, 11, 19, 42),
        source: AnswerSource.device,
        toolName: 'get_current_time',
      );
      final List<ChatMessage> back =
          MemoryService.decodeHistory(MemoryService.encodeHistory(<ChatMessage>[m]));
      expect(back.single.id, 'a1');
      expect(back.single.role, ChatRole.assistant);
      expect(back.single.text, m.text);
      expect(back.single.createdAt, m.createdAt);
      expect(back.single.source, AnswerSource.device);
      expect(back.single.toolName, 'get_current_time');
      expect(back.single.failed, isFalse);
    });

    test('corrupt storage degrades to empty, never throws', () {
      expect(MemoryService.decodeHistory('{not json'), isEmpty);
      expect(MemoryService.decodeHistory(null), isEmpty);
      expect(MemoryService.decodeHistory('{"role":"user"}'), isEmpty);
      expect(MemoryService.decodeTasks('[oops'), isEmpty);
    });

    test('history is capped, newest kept', () {
      final List<ChatMessage> many = <ChatMessage>[
        for (int i = 0; i < MemoryService.historyLimit + 15; i++)
          ChatMessage(
            id: '$i',
            role: ChatRole.user,
            text: 'm$i',
            createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          ),
      ];
      final List<ChatMessage> trimmed = MemoryService.trimHistory(many);
      expect(trimmed.length, MemoryService.historyLimit);
      expect(trimmed.last.text, 'm${many.length - 1}');
      expect(trimmed.first.text, 'm15');
    });
  });

  group('persistence', () {
    test('remember() writes, clearHistory() wipes', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final MemoryService memory =
          MemoryService(prefs: await SharedPreferences.getInstance());
      await memory.remember(ChatMessage(
        id: 'x',
        role: ChatRole.user,
        text: 'hello',
        createdAt: DateTime(2026, 10, 11),
      ));
      expect((await memory.loadHistory()).length, 1);
      await memory.clearHistory();
      expect(await memory.loadHistory(), isEmpty);
    });

    test('memory off = nothing is written', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final MemoryService memory =
          MemoryService(prefs: await SharedPreferences.getInstance())
            ..enabled = false;
      await memory.remember(ChatMessage(
        id: 'x',
        role: ChatRole.user,
        text: 'secret-ish',
        createdAt: DateTime(2026, 10, 11),
      ));
      expect(await memory.loadHistory(), isEmpty);
    });

    test('tasks round-trip through storage', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final MemoryService memory =
          MemoryService(prefs: await SharedPreferences.getInstance());
      await memory.replaceTasks(<TaskItem>[
        TaskItem(
          id: '1',
          title: 'दवा',
          createdAt: DateTime(2026, 10, 11),
        ),
      ]);
      final List<TaskItem> tasks = await memory.loadTasks();
      expect(tasks.single.title, 'दवा');
      expect(tasks.single.done, isFalse);
    });
  });
}
