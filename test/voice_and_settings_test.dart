import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_ai_agent/services/settings_service.dart';
import 'package:jarvis_ai_agent/services/voice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('voice error classification', () {
    test('permission denial is distinguishable from no-speech', () {
      expect(VoiceService.classifyError('Error while attempting to listen: '
          'android.speech.RecognitionServicePermission'),
          VoiceFailure.permissionDenied);
      expect(VoiceService.classifyError('errorNoMatch'), VoiceFailure.noMatch);
      expect(VoiceService.classifyError('errorNetwork'),
          VoiceFailure.needsNetwork);
      expect(VoiceService.classifyError('errorLanguageNotAvailable'),
          VoiceFailure.needsNetwork);
      expect(VoiceService.classifyError('SpeechRecognitionError msg: errorBusy'),
          VoiceFailure.recognizerBusy);
      expect(VoiceService.classifyError('something weird'),
          VoiceFailure.unknown);
    });

    test('failure enum always maps to a Hindi line', () {
      for (final VoiceFailure f in VoiceFailure.values) {
        expect(f.hindi.isEmpty, f == VoiceFailure.none, reason: f.name);
      }
    });
  });

  group('duplicate command guard', () {
    test('punctuation/case/spacing differences still count as duplicate', () {
      expect(VoiceService.isDuplicate('क्या समय है?', '  क्या   समय है '), isTrue);
      expect(VoiceService.isDuplicate('What time is it.', 'what time is it'),
          isTrue);
    });

    test('different commands and empty input are not duplicates', () {
      expect(VoiceService.isDuplicate('समय बताओ', 'तारीख़ बताओ'), isFalse);
      expect(VoiceService.isDuplicate('', ''), isFalse);
    });
  });

  group('settings', () {
    test('defaults are Hindi-first', () {
      const JarvisSettings s = JarvisSettings();
      expect(s.speechLocale, 'hi_IN');
      expect(s.ttsLanguage, 'hi-IN');
      expect(s.autoSpeak, isTrue);
      expect(s.rememberHistory, isTrue);
      expect(s.speakHindi, isTrue);
    });

    test('values round-trip and out-of-range numbers get clamped', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SettingsService.kTtsRate: 9.0,
        SettingsService.kTtsPitch: -3.0,
        SettingsService.kAutoSpeak: false,
        SettingsService.kSpeechLocale: 'en_IN',
      });
      final SettingsService service = SettingsService(
          prefs: await SharedPreferences.getInstance());
      final JarvisSettings loaded = await service.load();
      expect(loaded.ttsRate, 1.0, reason: 'max clamp');
      expect(loaded.ttsPitch, 0.5, reason: 'min clamp');
      expect(loaded.autoSpeak, isFalse);
      expect(loaded.speechLocale, 'en_IN');

      await service.save(loaded.copyWith(ttsRate: 0.4, replyLanguage: 'en'));
      final JarvisSettings again = await service.load();
      expect(again.ttsRate, 0.4);
      expect(again.replyLanguage, 'en');
    });
  });
}
