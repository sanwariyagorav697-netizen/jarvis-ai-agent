import 'dart:async';

// speech_to_text 7.x ne listen() ke kuch options SpeechListenOptions me shift
// kiye hain; purane named args abhi bhi supported hain aur version-stable hain.
// Deprecation *info* ke liye poora voice layer todna theek nahi tha.
// ignore_for_file: deprecated_member_use

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Voice input ke failure modes. UI inhe alag-alag Hindi message dikhata hai
/// (ek hi "कुछ गड़बड़" nahi).
enum VoiceFailure {
  none,
  unavailable,
  permissionDenied,
  noSpeech,
  noMatch,
  recognizerBusy,
  needsNetwork,
  unknown,
}

extension VoiceFailureText on VoiceFailure {
  String get hindi => switch (this) {
        VoiceFailure.none => '',
        VoiceFailure.unavailable =>
          'इस फ़ोन पर स्पीच रिकग्निशन सर्विस उपलब्ध नहीं है।',
        VoiceFailure.permissionDenied =>
          'माइक की परमिशन नहीं मिली। सेटिंग्स > ऐप्स > JARVIS > Permissions में माइक चालू करें।',
        VoiceFailure.noSpeech => 'कुछ सुनाई नहीं दिया — दोबारा बोलिए।',
        VoiceFailure.noMatch => 'आवाज़ साफ़ समझ नहीं आई। थोड़ा धीरे बोलिए।',
        VoiceFailure.recognizerBusy =>
          'स्पीच रिकग्निशन व्यस्त है। कुछ सेकंड बाद दोबारा कोशिश करें।',
        VoiceFailure.needsNetwork =>
          'स्पीच रिकग्निशन को नेटवर्क चाहिए (offline हिंदी पैक इंस्टॉल नहीं है)।',
        VoiceFailure.unknown => 'स्पीच रिकग्निशन फेल हो गया।',
      };
}

/// Android SpeechRecognizer ka patla wrapper.
/// Ek tap = ek listening session = ek final string (ya null + reason).
class VoiceService {
  VoiceService({stt.SpeechToText? speech})
      : _speech = speech ?? stt.SpeechToText();

  final stt.SpeechToText _speech;

  bool _initialized = false;
  VoiceFailure lastFailure = VoiceFailure.none;
  String? _lastErrorText;

  bool get isInitialized => _initialized;
  String? get lastErrorText => _lastErrorText;

  bool get isListening {
    try {
      return _speech.isListening;
    } on Object {
      // initialize() se pehle plugin exception de sakta hai — tab "नहीं सुन रहे".
      return false;
    }
  }

  /// Lifecycle me ek baar. false = mic permission ya speech service nahi.
  Future<bool> initialize() async {
    try {
      _initialized = await _speech.initialize(
        debugLogging: false,
        onError: (Object error) {
          lastFailure = classifyError(error.toString());
          _lastErrorText = error.toString();
        },
      );
    } on Object catch (e) {
      _initialized = false;
      _lastErrorText = e.toString();
      lastFailure = VoiceFailure.unavailable;
    }
    return _initialized;
  }

  /// null = kuch useable nahi mila (tab [lastFailure] dekhein).
  Future<String?> listenOnce({
    required String localeId,
    Duration maxDuration = const Duration(seconds: 12),
    Duration silenceTimeout = const Duration(seconds: 4),
    void Function(double level)? onLevel,
    void Function(String partial)? onPartial,
  }) async {
    lastFailure = VoiceFailure.none;
    _lastErrorText = null;

    if (!_initialized && !await initialize()) {
      if (lastFailure == VoiceFailure.none) {
        lastFailure = VoiceFailure.unavailable;
      }
      return null;
    }

    final Completer<String> done = Completer<String>();
    String latest = '';

    void finish(String value) {
      if (!done.isCompleted) {
        done.complete(value);
      }
    }

    late final Future<void> session;
    try {
      session = _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          final String words = result.recognizedWords;
          if (words.isNotEmpty) {
            latest = words;
            onPartial?.call(words);
          }
          if (result.finalResult) {
            finish(words);
          }
        },
        onSoundLevelChange:
            onLevel == null ? null : (double level) => onLevel(level),
        localeId: localeId,
        listenFor: maxDuration,
        pauseFor: silenceTimeout,
        partialResults: true,
        cancelOnError: false,
      );
    } on Object catch (e) {
      _lastErrorText = e.toString();
      lastFailure = classifyError(e.toString());
      return null;
    }

    // Teen me jo pehle ho: final result, session ka natural end, ya hard cap.
    final String? settled = await Future.any<String?>(<Future<String?>>[
      done.future,
      session.then((_) => latest),
      Future<String?>.delayed(
          maxDuration + const Duration(milliseconds: 600), () => latest),
    ]);

    final String text = (settled ?? '').trim();
    if (text.isEmpty) {
      if (lastFailure == VoiceFailure.none) {
        lastFailure = VoiceFailure.noSpeech;
      }
      return null;
    }
    return text;
  }

  Future<void> stop() => _quietly(() => _speech.stop());

  Future<void> cancel() => _quietly(() => _speech.cancel());

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Session pehle hi khatam ho chuka ho to plugin exception deta hai.
      // Ise user-facing error nahi banate.
    }
  }

  /// Plugin error ka raw text (version ke hisaab se shape badalta hai) ko ek
  /// stable enum me map karta hai.
  static VoiceFailure classifyError(String raw) {
    // Spaces hataakar match karte hain: plugin 'errorLanguageNotAvailable' jaise
    // camelCase codes bhi bhejta hai aur 'no speech' jaise phrases bhi.
    final String s =
        raw.toLowerCase().replaceAll(RegExp(r'[\s_]+'), '').trim();
    if (s.contains('permission') || s.contains('notgranted')) {
      return VoiceFailure.permissionDenied;
    }
    if (s.contains('nospeech') || s.contains('silence')) {
      return VoiceFailure.noSpeech;
    }
    if (s.contains('nomatch')) {
      return VoiceFailure.noMatch;
    }
    if (s.contains('busy') || s.contains('inuse')) {
      return VoiceFailure.recognizerBusy;
    }
    if (s.contains('network') ||
        s.contains('offline') ||
        s.contains('languagenotavailable')) {
      return VoiceFailure.needsNetwork;
    }
    if (s.contains('notavailable') || s.contains('notinitialized')) {
      return VoiceFailure.unavailable;
    }
    return VoiceFailure.unknown;
  }

  /// Duplicate-command guard: normalize karke compare.
  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool isDuplicate(String previous, String next) {
    final String a = normalize(previous);
    return a.isNotEmpty && a == normalize(next);
  }
}
