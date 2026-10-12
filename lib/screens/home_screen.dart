import 'dart:async';

import 'package:flutter/material.dart';

import '../app/jarvis_theme.dart';
import '../models/assistant_status.dart';
import '../models/tool_result.dart';
import '../services/assistant_controller.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/jarvis_orb.dart';
import '../widgets/status_strip.dart';
import 'settings_screen.dart';

/// Main JARVIS screen: orb + live transcript + conversation + mic/typing input.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AssistantController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  AssistantController get c => widget.controller;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _inputFocus.unfocus();
    await c.submitText(text);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => SettingsScreen(controller: c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (BuildContext context, Widget? _) {
        final bool listening = c.status == AssistantStatus.listening;
        final bool canInterrupt = c.status == AssistantStatus.speaking;
        return Scaffold(
          appBar: AppBar(
            title: const Text('J.A.R.V.I.S'),
            actions: <Widget>[
              IconButton(
                onPressed: _openSettings,
                icon: const Icon(Icons.tune),
                tooltip: 'सेटिंग्स',
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Column(
                children: <Widget>[
                  const StatusStrip(controller: c),
                  const SizedBox(height: 8),
                  JarvisOrb(status: c.status, level: c.micLevel, size: 150),
                  const SizedBox(height: 6),
                  Text(
                    c.statusDetail.isEmpty
                        ? c.status.hindiHint
                        : c.statusDetail,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.status == AssistantStatus.error
                          ? JarvisPalette.error
                          : JarvisPalette.dimText,
                      height: 1.35,
                    ),
                  ),
                  if (c.lastToolResults.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        children: c.lastToolResults
                            .map((ToolResult r) => _ToolChip(result: r))
                            .toList(growable: false),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: c.messages.isEmpty
                        ? const Center(
                            child: Text(
                              'नमस्ते। माइक दबाकर बोलिए, या नीचे टाइप कीजिए।\n'
                              'जैसे: “अभी क्या समय है?” या “दवा याद दिलाओ”',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: JarvisPalette.dimText, height: 1.5),
                            ),
                          )
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.only(bottom: 6),
                            itemCount: c.messages.length,
                            itemBuilder: (BuildContext context, int index) {
                              final int i = c.messages.length - 1 - index;
                              return ChatBubble(message: c.messages[i]);
                            },
                          ),
                  ),
                  if (listening && c.partialHeard.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 4),
                        child: Text(
                          'सुना: ${c.partialHeard}',
                          style: const TextStyle(
                              color: JarvisPalette.cyan, fontSize: 12),
                        ),
                      ),
                    ),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _input,
                          focusNode: _inputFocus,
                          textInputAction: TextInputAction.send,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'यहाँ टाइप भी कर सकते हैं…',
                            hintStyle:
                                TextStyle(color: JarvisPalette.dimText),
                            filled: true,
                            fillColor: JarvisPalette.panel,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(14)),
                            ),
                          ),
                          onSubmitted: (String _) => _send(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        onPressed: _send,
                        icon: const Icon(Icons.send),
                        tooltip: 'भेजें',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      IconButton(
                        onPressed: canInterrupt ? c.stopSpeaking : null,
                        icon: const Icon(Icons.stop_circle_outlined),
                        iconSize: 34,
                        color: JarvisPalette.warning,
                        tooltip: 'बोलना रोकें',
                      ),
                      _MicButton(
                        listening: listening,
                        busy: c.busy,
                        onTap: listening
                            ? c.stopListening
                            : () => unawaited(c.startListening()),
                      ),
                      IconButton(
                        onPressed: c.lastSpokenText == null
                            ? null
                            : c.repeatLast,
                        icon: const Icon(Icons.replay),
                        iconSize: 30,
                        color: JarvisPalette.cyan,
                        tooltip: 'जवाब दोहराएँ',
                      ),
                    ],
                  ),
                  Text(
                    listening ? 'रोकने के लिए माइक दोबारा दबाएँ' : 'बोलने के लिए माइक दबाएँ',
                    style: const TextStyle(
                        fontSize: 11, color: JarvisPalette.dimText),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.listening,
    required this.busy,
    required this.onTap,
  });

  final bool listening;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color =
        listening ? JarvisPalette.error : JarvisPalette.cyan;
    return GestureDetector(
      onTap: busy && !listening ? null : onTap,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: JarvisPalette.panelSoft,
          border: Border.all(color: color, width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: listening ? 0.45 : 0.2),
              blurRadius: listening ? 24 : 12,
              spreadRadius: listening ? 3 : 0,
            ),
          ],
        ),
        child: Icon(
          listening ? Icons.mic : Icons.mic_none,
          size: 36,
          color: color,
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.result});

  final ToolResult result;

  @override
  Widget build(BuildContext context) {
    final bool ok = result.isSuccess;
    final Color color =
        ok ? JarvisPalette.success : JarvisPalette.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        '${ok ? '✓' : '✕'} ${result.toolName} · ${result.outcome.name}',
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}
