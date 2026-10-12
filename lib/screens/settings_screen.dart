import 'package:flutter/material.dart';

import '../app/jarvis_theme.dart';
import '../services/assistant_controller.dart';
import '../services/settings_service.dart';

/// Settings: bhasha, आवाज़, मेमोरी। भविष्य में यहीं AI provider + key भी।
///
/// यहाँ कोई field secret store नहीं करती — API key (Phase 4) secure storage
/// me jayegi, is screen ke neeche uska note है।
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AssistantController controller;

  Future<void> _save(JarvisSettings next) async {
    await controller.updateSettings(next);
  }

  Future<void> _confirmErase(BuildContext context) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: JarvisPalette.panel,
        title: const Text('हिस्टरी मिटाएँ?'),
        content: const Text(
            'इस फ़ोन पर सेव की गई सारी बातचीत हट जाएगी। यह वापस नहीं आएगी।'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('रहने दें'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('हाँ, मिटाएँ'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await controller.eraseHistory();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('हिस्टरी मिटा दी गई।')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final JarvisSettings s = controller.settings;
        return Scaffold(
          appBar: AppBar(title: const Text('सेटिंग्स')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: <Widget>[
                _Section(
                  title: 'सुनने की भाषा (Speech recognition)',
                  child: Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final MapEntry<String, String> e
                          in const <String, String>{
                        'hi_IN': 'हिंदी',
                        'en_IN': 'English (India)',
                        'en-US': 'English (US)',
                      }.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: s.speechLocale == e.key,
                          onSelected: (bool _) =>
                              _save(s.copyWith(speechLocale: e.key)),
                        ),
                    ],
                  ),
                  note: 'हिंदी तभी चलेगी जब फ़ोन में Google/भाषा इंजन के हिंदी '
                      'डेटा मौजूद हों।',
                ),
                _Section(
                  title: 'बोलने की आवाज़ (Text to speech)',
                  child: Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final MapEntry<String, String> e
                          in const <String, String>{
                        'hi-IN': 'हिंदी',
                        'en-IN': 'English (India)',
                        'en-US': 'English (US)',
                      }.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: s.ttsLanguage == e.key,
                          onSelected: (bool _) =>
                              _save(s.copyWith(ttsLanguage: e.key)),
                        ),
                    ],
                  ),
                  note: controller.ttsLanguageOk == false
                      ? 'चेतावनी: इस फ़ोन पर इस भाषा का वॉइस इंस्टॉल नहीं मिला। '
                          'फ़ोन की सेटिंग्स > सिस्टम > भाषाएँ > टेक्स्ट-टू-स्पीच '
                          'में जाकर यह भाषा डाउनलोड/एनेबल करें।'
                      : 'जवाब इसी भाषा में बोले जाएँगे।',
                ),
                _Section(
                  title: 'आवाज़ की रफ़्तार',
                  child: Column(
                    children: <Widget>[
                      Slider(
                        min: 0.2,
                        max: 1.0,
                        divisions: 8,
                        value: s.ttsRate,
                        label: s.ttsRate.toStringAsFixed(1),
                        onChanged: (double v) =>
                            _save(s.copyWith(ttsRate: v)),
                      ),
                      Slider(
                        min: 0.5,
                        max: 2.0,
                        divisions: 6,
                        value: s.ttsPitch,
                        label: 'pitch ${s.ttsPitch.toStringAsFixed(1)}',
                        onChanged: (double v) =>
                            _save(s.copyWith(ttsPitch: v)),
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: 'व्यवहार',
                  child: Column(
                    children: <Widget>[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: s.autoSpeak,
                        title: const Text('जवाब बोलकर सुनाएँ'),
                        onChanged: (bool v) =>
                            _save(s.copyWith(autoSpeak: v)),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: s.rememberHistory,
                        title: const Text('बातचीत याद रखें (इसी फ़ोन पर)'),
                        subtitle: const Text(
                            'ऑफ़ करने पर हिस्टरी सेव नहीं होगी। पासवर्ड/API key '
                            'कभी मेमोरी में नहीं रखे जाते।',
                            style: TextStyle(fontSize: 12)),
                        onChanged: (bool v) =>
                            _save(s.copyWith(rememberHistory: v)),
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () async {
                        final bool ok = await controller.testVoice();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok
                                  ? 'आवाज़ ठीक चली।'
                                  : 'आवाज़ नहीं चली — ऊपर दिया गया workaround देखें।'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.volume_up),
                      label: const Text('आवाज़ टेस्ट करें'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _confirmErase(context),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('हिस्टरी मिटाएँ'),
                    ),
                  ],
                ),
                _Section(
                  title: 'डेटा और सुरक्षा',
                  child: Text(
                    'अभी: समय/तारीख़ और कामों की लिस्ट पूरी तरह डिवाइस पर बनती '
                    'है — कोई नेटवर्क कॉल नहीं। ऑनलाइन AI जुड़ने के बाद आपका '
                    'सवाल चुने हुए provider के सर्वर पर HTTPS से जाएगा, और key '
                    'एंड्रॉइड की secured storage में रहेगी (GitHub/APK में नहीं)।',
                    style: const TextStyle(height: 1.5, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.note,
    this.actions = const <Widget>[],
  });

  final String title;
  final Widget child;
  final String? note;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: jarvisPanel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: JarvisPalette.cyan,
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
          if (note != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              note!,
              style: const TextStyle(
                  color: JarvisPalette.dimText, fontSize: 11.5, height: 1.4),
            ),
          ],
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 8, children: actions),
            ),
        ],
      ),
    );
  }
}
