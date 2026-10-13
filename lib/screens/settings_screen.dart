import 'package:flutter/material.dart';

import '../app/jarvis_theme.dart';
import '../services/ai/ai_config.dart';
import '../services/ai/ai_service.dart';
import '../services/ai/gemini_service.dart';
import '../services/ai/openai_compat_service.dart';
import '../services/assistant_controller.dart';
import '../services/settings_service.dart';

/// Settings: bhasha, आवाज़, मेमोरी, और ऑनलाइन AI (provider + model + key)।
///
/// Secret rule: API key ka text box sirf Android Keystore-backed secure
/// storage me jaता है (_AiSection ke `saveApiKey` se) — JarvisSettings /
/// SharedPreferences me कभी नहीं, aur na ही UI me poorी key lautती है (सिर्फ़
/// last 4 characters दिखते हैं)।
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
                _AiSection(controller: controller),
                _Section(
                  title: 'सुनने की भाषा (Speech recognition)',
                  body: Wrap(
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
                  body: Wrap(
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
                  body: Column(
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
                  body: Column(
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
                  body: Text(
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
    required this.body,
    this.note,
    this.actions = const <Widget>[],
  });

  final String title;
  final Widget body;
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
          body,
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

/// AI provider + model + API key का हिस्सा. अलग StatefulWidget इसलिए कि its
/// text controllers is section ke saath ही मरते हैं (memory leak से बचाव)।
class _AiSection extends StatefulWidget {
  const _AiSection({required this.controller});

  final AssistantController controller;

  @override
  State<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends State<_AiSection> {
  final TextEditingController _model = TextEditingController();
  final TextEditingController _baseUrl = TextEditingController();
  final TextEditingController _key = TextEditingController();
  bool _showKey = false;
  String _result = '';
  bool _resultOk = false;

  @override
  void initState() {
    super.initState();
    _model.text = widget.controller.settings.aiModel;
    _baseUrl.text = widget.controller.settings.aiBaseUrl;
  }

  @override
  void dispose() {
    _model.dispose();
    _baseUrl.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _saveSettings(JarvisSettings next) =>
      widget.controller.updateSettings(next);

  Future<void> _saveKey() async {
    final String? error = await widget.controller.saveApiKey(_key.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _resultOk = error == null;
      _result = error == null
          ? 'key secure storage में सेव हो गई (आपके फ़ोन पर, GitHub/APK में नहीं)।'
          : error;
      if (error == null) {
        _key.clear();
      }
    });
  }

  Future<void> _clearKey() async {
    final bool cleared = await widget.controller.clearApiKey();
    if (!mounted) {
      return;
    }
    setState(() {
      _resultOk = cleared;
      _result = cleared
          ? 'key इस फ़ोन से मिटा दी गई।'
          : 'key मिटाई नहीं जा सकी — फ़ोन की storage में दिक्कत है।';
    });
  }

  Future<void> _test() async {
    setState(() => _result = 'टेस्ट हो रहा है… (एक छोटी API कॉल)');
    final AiHealth health = await widget.controller.testAiConnection();
    if (!mounted) {
      return;
    }
    setState(() {
      _resultOk = health.ok;
      _result = health.ok
          ? '✓ ${health.message}\nनमूना जवाब: ${health.sample}'
          : '✗ ${health.message}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final AssistantController controller = widget.controller;
    final JarvisSettings s = controller.settings;
    final AiProvider provider = controller.aiProvider;
    final bool online = provider.isOnline;
    final List<String> models = provider == AiProvider.gemini
        ? GeminiService.suggestedModels
        : OpenAiCompatService.suggestedModels;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Section(
          title: 'ऑनलाइन AI (ज़रूरी नहीं — पहले सिर्फ़ डिवाइस टूल भी चलेंगे)',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final AiProvider p in AiProvider.values)
                    ChoiceChip(
                      label: Text(p.label),
                      selected: s.aiProvider == p.name,
                      onSelected: (bool _) =>
                          _saveSettings(s.copyWith(aiProvider: p.name)),
                    ),
                ],
              ),
              if (online) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  'मॉडल (खाली छोड़ें तो default: '
                  '${AiConfig.defaultModelFor(provider)})',
                  style: const TextStyle(fontSize: 12),
                ),
                TextField(
                  controller: _model,
                  autocorrect: false,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (String v) =>
                      _saveSettings(s.copyWith(aiModel: v.trim())),
                ),
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    for (final String m in models)
                      ActionChip(
                        label: Text(m),
                        onPressed: () {
                          _model.text = m;
                          _saveSettings(s.copyWith(aiModel: m));
                        },
                      ),
                  ],
                ),
              ],
              if (provider == AiProvider.openaiCompatible) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  'Base URL (Groq/OpenRouter/आपका backend) — खाली = '
                  '${OpenAiCompatService.defaultBaseUrl}',
                  style: const TextStyle(fontSize: 12),
                ),
                TextField(
                  controller: _baseUrl,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (String v) =>
                      _saveSettings(s.copyWith(aiBaseUrl: v.trim())),
                ),
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    ActionChip(
                      label: const Text('Groq'),
                      onPressed: () {
                        _baseUrl.text = OpenAiCompatService.defaultBaseUrl;
                        _saveSettings(
                            s.copyWith(aiBaseUrl: OpenAiCompatService.defaultBaseUrl));
                      },
                    ),
                    ActionChip(
                      label: const Text('OpenRouter'),
                      onPressed: () {
                        _baseUrl.text = OpenAiCompatService.openRouterBaseUrl;
                        _saveSettings(s.copyWith(
                            aiBaseUrl: OpenAiCompatService.openRouterBaseUrl));
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                controller.aiConfigured
                    ? 'key सेव है: ${controller.aiKeyMasked} (सिर्फ़ last 4 दिख रहे हैं)'
                    : 'key सेव नहीं है — नीचे डालिए।',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          note: controller.aiSummary +
              '. \nफ्री tier की सीमा: ~15 अनुरोध/मिनट और कई सौ/दिन (Google इसे बदल सकता है) — '

                  'इसलिए समय/तारीख़ और कामों के हुक्म नेट पर जाने से बचाने के लिए फोन पर ही चलते हैं।',
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: controller.testingAi ? null : _test,
              icon: const Icon(Icons.wifi_tethering),
              label: Text(controller.testingAi ? 'टेस्ट हो रहा है…' : 'Test API Connection'),
            ),
            if (_result.isNotEmpty)
              Text(
                _result,
                style: TextStyle(
                  fontSize: 12,
                  color: _resultOk ? JarvisPalette.success : JarvisPalette.error,
                ),
              ),
          ],
        ),
        if (online)
          _Section(
            title: 'API key (सिर्फ़ इस फ़ोन पर)',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: _key,
                  obscureText: !_showKey,
                  autocorrect: false,
                  maxLines: 1,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: provider == AiProvider.gemini
                        ? 'AIza… (aistudio.google.com/apikey से)'
                        : 'gsk_… / sk-or-…',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _showKey = !_showKey),
                      icon: Icon(_showKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'key यहाँ paste करते ही Android की secured storage में जाती है। यह '

                  'GitHub, APK assets, logs या हिस्टरी में नहीं डाली जाती, और ऐप उसे सिर्फ़ '

                  'API कॉल के header में ही भेजता है।',
                  style: TextStyle(fontSize: 11.5, height: 1.4),
                ),
              ],
            ),
            actions: <Widget>[
              FilledButton.icon(
                onPressed: _saveKey,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Save key'),
              ),
              OutlinedButton.icon(
                onPressed: controller.aiConfigured ? _clearKey : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('मिटाएँ'),
              ),
            ],
          ),
      ],
    );
  }
}
