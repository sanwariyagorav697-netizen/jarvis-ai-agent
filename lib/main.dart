import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/jarvis_theme.dart';
import 'screens/home_screen.dart';
import 'services/assistant_controller.dart';
import 'services/memory_service.dart';
import 'services/settings_service.dart';
import 'services/tool_registry.dart';
import 'services/tts_service.dart';
import 'services/voice_service.dart';
import 'tools/current_time_tool.dart';
import 'tools/task_tools.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: JarvisPalette.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const JarvisApp());
}

class JarvisApp extends StatefulWidget {
  const JarvisApp({super.key});

  @override
  State<JarvisApp> createState() => _JarvisAppState();
}

class _JarvisAppState extends State<JarvisApp> {
  late final AssistantController _controller;
  late final TtsService _tts;
  late final VoiceService _voice;

  @override
  void initState() {
    super.initState();
    // Composition root: services yahan bante hain, screens ko sirf controller
    // milta hai. Isse AI provider (Phase 4) badalna ek jagee kaam rahega.
    final MemoryService memory = MemoryService();
    _tts = TtsService();
    _voice = VoiceService();
    _controller = AssistantController(
      settingsService: SettingsService(),
      memory: memory,
      tts: _tts,
      voice: _voice,
      registry: ToolRegistry(<JarvisTool>[
        CurrentTimeTool(),
        AddTaskTool(memory),
        ListTasksTool(memory),
        CompleteTaskTool(memory),
      ]),
    );
    _controller.boot();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JARVIS',
      debugShowCheckedModeBanner: false,
      theme: buildJarvisTheme(),
      home: HomeScreen(controller: _controller),
    );
  }
}
