import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// Android TextToSpeech engine ka wrapper.
///
/// [speak] tab tak await karta hai jab tak bolna khatam (ya engine ne reason
/// ke saath rok diya) — isse assistant ka state machine "bol raha hai" me
/// atakta nahi hai.
class TtsService {
  TtsService({FlutterTts? engine}) : _tts = engine ?? FlutterTts() {
    _tts.awaitSpeakCompletion(true);
  }

  final FlutterTts _tts;

  String _language = 'hi-IN';
  double _rate = 0.5;
  double _pitch = 1.0;
  bool _prepared = false;
  bool _speaking = false;

  bool get isSpeaking => _speaking;
  String get language => _language;
  double get rate => _rate;

  Future<void> configure({
    required String language,
    required double rate,
    required double pitch,
  }) async {
    _language = language;
    _rate = rate;
    _pitch = pitch;
    _prepared = false;
    await _apply();
  }

  Future<void> _apply() async {
    try {
      await _tts.setLanguage(_language);
      await _tts.setSpeechRate(_rate);
      await _tts.setPitch(_pitch);
      _prepared = true;
    } on Object {
      _prepared = false;
    }
  }

  /// true = engine ne bola (ya kam se kam accept karke pura kiya).
  /// false = language/voice nahi mila ya engine fail hua — UI isse "बोल नहीं
  /// पाया" dikhata hai, chup-chaap success nahi.
  Future<bool> speak(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (!_prepared) {
      await _apply();
    }
    try {
      await _tts.setLanguage(_language);
    } on Object {
      // language set na ho paye to bhi bolne ki koshish karte hain
    }

    _speaking = true;
    try {
      // Lamba jawab + slow rate = zyada time; text length se estimate, 3 min cap.
      final Duration budget = Duration(
        milliseconds: (1500 + trimmed.length * 110).clamp(3000, 180000),
      );
      await _tts.speak(trimmed).timeout(budget, onTimeout: () {
        // Engine ne completion nahi bheja — bolti band karwate hain.
        unawaited(_tts.stop());
        return null;
      });
      return true;
    } on Object {
      return false;
    } finally {
      _speaking = false;
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // nothing to stop
    }
    _speaking = false;
  }

  /// Device par is language ka voice install hai ya nahi.
  /// Plugin/platform version ke hisaab se return type badalta hai, isliye
  /// dynamic ko manually interpret kiya gaya hai.
  Future<bool?> languageInstalled(String code) async {
    try {
      final Object? result = await _tts.isLanguageInstalled(code);
      return result == true || result == 1;
    } on Object {
      try {
        final Object? result = await _tts.isLanguageAvailable(code);
        return result == true || result == 1;
      } on Object {
        return null; // platform ne jawab hi nahi diya → UI "अज्ञात" dikhayega
      }
    }
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } on Object {
      // ignore
    }
  }
}
