import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/task_item.dart';

/// User-controlled memory.
///
/// - Sirf device par store hota hai (SharedPreferences, app-private area).
/// - User history ko dekh/edit/mita sakta hai (Settings screen).
/// - `enabled = false` karne par kuch persist nahi hota.
/// - API key / password yahan KABHI store nahi karte — is file me koi secret
///   field jaan-boojh ke nahi hai.
class MemoryService {
  MemoryService({SharedPreferences? prefs}) : _prefs = prefs;

  static const String kHistory = 'jarvis.history';
  static const String kTasks = 'jarvis.tasks';
  static const int historyLimit = 40;

  bool enabled = true;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _store() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<List<ChatMessage>> loadHistory() async {
    final SharedPreferences p = await _store();
    return decodeHistory(p.getString(kHistory));
  }

  Future<void> remember(ChatMessage message) async {
    if (!enabled) return;
    final SharedPreferences p = await _store();
    final List<ChatMessage> all = decodeHistory(p.getString(kHistory))
      ..add(message);
    await p.setString(kHistory, encodeHistory(trimHistory(all)));
  }

  Future<void> clearHistory() async {
    final SharedPreferences p = await _store();
    await p.remove(kHistory);
  }

  Future<List<TaskItem>> loadTasks() async {
    final SharedPreferences p = await _store();
    return decodeTasks(p.getString(kTasks));
  }

  Future<void> replaceTasks(List<TaskItem> tasks) async {
    final SharedPreferences p = await _store();
    await p.setString(kTasks, encodeTasks(tasks));
  }

  // ---------- pure helpers (unit-tested) ----------

  static List<ChatMessage> trimHistory(List<ChatMessage> messages) =>
      messages.length <= historyLimit
          ? messages
          : messages.sublist(messages.length - historyLimit);

  static String encodeHistory(List<ChatMessage> messages) => jsonEncode(
      messages.map((ChatMessage m) => m.toJson()).toList(growable: false));

  static List<ChatMessage> decodeHistory(String? raw) {
    if (raw == null || raw.isEmpty) return <ChatMessage>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <ChatMessage>[];
      return decoded
          .whereType<Map<String, Object?>>()
          .map(ChatMessage.fromJson)
          .toList();
    } on FormatException {
      // Corrupt storage = history nahi, crash nahi.
      return <ChatMessage>[];
    }
  }

  static String encodeTasks(List<TaskItem> tasks) =>
      jsonEncode(tasks.map((TaskItem t) => t.toJson()).toList(growable: false));

  static List<TaskItem> decodeTasks(String? raw) {
    if (raw == null || raw.isEmpty) return <TaskItem>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <TaskItem>[];
      return decoded
          .whereType<Map<String, Object?>>()
          .map(TaskItem.fromJson)
          .toList();
    } on FormatException {
      return <TaskItem>[];
    }
  }
}
