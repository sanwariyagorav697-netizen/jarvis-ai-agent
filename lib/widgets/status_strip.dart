import 'package:flutter/material.dart';

import '../app/jarvis_theme.dart';
import '../services/assistant_controller.dart';

/// Permission + connection indicators. Jhoothi green nahi — jab tak platform
/// haan na kahe, chip laal/pitili rehti hai.
class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key, required this.controller});

  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final bool micOk = controller.voiceAvailable;
    final bool? ttsOk = controller.ttsLanguageOk;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: <Widget>[
        _Chip(
          label: micOk ? 'माइक चालू' : 'माइक बंद',
          icon: micOk ? Icons.mic : Icons.mic_off,
          color: micOk ? JarvisPalette.success : JarvisPalette.error,
        ),
        _Chip(
          label: switch (ttsOk) {
            true => '${controller.settings.ttsLanguage} वॉइस तैयार',
            false => '${controller.settings.ttsLanguage} वॉइस इंस्टॉल करें',
            _ => 'वॉइस स्थिति अज्ञात',
          },
          icon: Icons.record_voice_over_outlined,
          color: switch (ttsOk) {
            true => JarvisPalette.success,
            false => JarvisPalette.warning,
            _ => JarvisPalette.dimText,
          },
        ),
        _Chip(
          label: controller.settings.rememberHistory
              ? 'मेमोरी ऑन (फ़ोन पर)'
              : 'मेमोरी ऑफ़',
          icon: Icons.inventory_2_outlined,
          color: JarvisPalette.dimText,
        ),
        _Chip(
          label: 'मोड: लोकल टूल्स (AI फेज़ 4)',
          icon: Icons.memory,
          color: JarvisPalette.dimText,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(fontSize: 11, color: color, height: 1.1)),
        ],
      ),
    );
  }
}
