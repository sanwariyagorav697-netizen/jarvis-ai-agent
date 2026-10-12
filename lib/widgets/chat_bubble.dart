import 'package:flutter/material.dart';

import '../app/jarvis_theme.dart';
import '../models/chat_message.dart';

/// Ek conversation line. Role + source (device/online/tool) hamesha dikhta hai,
/// taaki user ko pata rahe jawab kahan se aaya.
class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool fromUser = message.role == ChatRole.user;
    final Color accent = message.failed
        ? JarvisPalette.error
        : switch (message.role) {
            ChatRole.user => JarvisPalette.blue,
            ChatRole.assistant => JarvisPalette.cyan,
            ChatRole.tool => JarvisPalette.success,
            ChatRole.system => JarvisPalette.warning,
          };

    final String? source = message.source?.label;

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        decoration: jarvisPanel(
          borderColor: accent.withValues(alpha: 0.65),
          fillColor: fromUser
              ? JarvisPalette.panelSoft
              : JarvisPalette.panel.withValues(alpha: 0.9),
          radius: 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  message.role.label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (source != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Text(
                    source,
                    style: const TextStyle(
                        color: JarvisPalette.dimText, fontSize: 10),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              message.text,
              style: TextStyle(
                fontSize: message.role == ChatRole.tool ? 12 : 15,
                color: message.role == ChatRole.tool
                    ? JarvisPalette.dimText
                    : null,
                fontFamily:
                    message.role == ChatRole.tool ? 'monospace' : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
