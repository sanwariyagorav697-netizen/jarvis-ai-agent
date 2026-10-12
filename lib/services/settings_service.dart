import 'package:shared_preferences/shared_preferences.dart';

/// App ki poori user-controlled settings. Sab kuch device par rehta hai
/// (SharedPreferences), kuch bhi network par nahi jata — API key alag se
/// secure storage me jayegi (Phase 4), yahan nahi.
class JarvisSettings {
  const JarvisSettings({
    this.replyLanguage = 'auto',
    this.speechLocale = 'hi_IN',
    this.ttsLanguage = 'hi-IN',
    this.ttsRate = 0.5,
    this.ttsPitch = 1.0,
    this.autoSpeak = true,
    this.rememberHistory = true,
  });

  /// 'auto' = jo bhasha user bola, wahi; 'hi' | 'en' = force.
  final String replyLanguage;

  /// Android SpeechRecognizer ka locale (underscore wala format).
  final String speechLocale;

  /// TextToSpeech ka locale (hyphen wala format).
  final String ttsLanguage;

  /// flutter_tts ka rate 0.0..1.0 (Android par 0.5 = normal).
  final double ttsRate;
  final double ttsPitch;

  /// false karne par jawab sirf screen par aayega, bola nahi jayega.
  final bool autoSpeak;

  /// false = conversation history save nahi hogi (app band karte hi sab delete).
  final bool rememberHistory;

  JarvisSettings copyWith({
    String? replyLanguage,
    String? speechLocale,
    String? ttsLanguage,
    double? ttsRate,
    double? ttsPitch,
    bool? autoSpeak,
    bool? rememberHistory,
  }) {
    return JarvisSettings(
      replyLanguage: replyLanguage ?? this.replyLanguage,
      speechLocale: speechLocale ?? this.speechLocale,
      ttsLanguage: ttsLanguage ?? this.ttsLanguage,
      ttsRate: ttsRate ?? this.ttsRate,
      ttsPitch: ttsPitch ?? this.ttsPitch,
      autoSpeak: autoSpeak ?? this.autoSpeak,
      rememberHistory: rememberHistory ?? this.rememberHistory,
    );
  }

  bool get speakHindi => !ttsLanguage.startsWith('en');
}

class SettingsService {
  SettingsService({SharedPreferences? prefs}) : _prefs = prefs;

  static const String kReplyLanguage = 'jarvis.reply_language';
  static const String kSpeechLocale = 'jarvis.speech_locale';
  static const String kTtsLanguage = 'jarvis.tts_language';
  static const String kTtsRate = 'jarvis.tts_rate';
  static const String kTtsPitch = 'jarvis.tts_pitch';
  static const String kAutoSpeak = 'jarvis.auto_speak';
  static const String kRememberHistory = 'jarvis.remember_history';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _store() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<JarvisSettings> load() async {
    final SharedPreferences p = await _store();
    const JarvisSettings d = JarvisSettings();
    return JarvisSettings(
      replyLanguage: p.getString(kReplyLanguage) ?? d.replyLanguage,
      speechLocale: p.getString(kSpeechLocale) ?? d.speechLocale,
      ttsLanguage: p.getString(kTtsLanguage) ?? d.ttsLanguage,
      ttsRate: (p.getDouble(kTtsRate) ?? d.ttsRate).clamp(0.2, 1.0).toDouble(),
      ttsPitch: (p.getDouble(kTtsPitch) ?? d.ttsPitch).clamp(0.5, 2.0).toDouble(),
      autoSpeak: p.getBool(kAutoSpeak) ?? d.autoSpeak,
      rememberHistory: p.getBool(kRememberHistory) ?? d.rememberHistory,
    );
  }

  Future<void> save(JarvisSettings s) async {
    final SharedPreferences p = await _store();
    await p.setString(kReplyLanguage, s.replyLanguage);
    await p.setString(kSpeechLocale, s.speechLocale);
    await p.setString(kTtsLanguage, s.ttsLanguage);
    await p.setDouble(kTtsRate, s.ttsRate);
    await p.setDouble(kTtsPitch, s.ttsPitch);
    await p.setBool(kAutoSpeak, s.autoSpeak);
    await p.setBool(kRememberHistory, s.rememberHistory);
  }
}
