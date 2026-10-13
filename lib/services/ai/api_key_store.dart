import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_config.dart';

/// Secret store ka patla interface — isse unit tests me fake se replace kiya जा
/// सकता है (plugin test environment me platform channel nahi chalaता)।
abstract class KeyValueSecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Android Keystore-backed real implementation (RSA OAEP + AES-GCM, v10+)।
/// Key: APK assets me nahi, git me nahi, SharedPreferences (plain XML) me nahi।
class FlutterSecureKeyValueStore implements KeyValueSecretStore {
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// API keys ka storage + entry validation (secure storage ke upar).
class JarvisApiKeyStore {
  JarvisApiKeyStore({KeyValueSecretStore? store})
      : _store = store ?? FlutterSecureKeyValueStore();

  /// Gemini/OpenAI keys 30-60 chars की होती हैं; 200 hard cap (request-size
  /// safety) और 16 min (typical valid key से छोटी चीज़ reject)।
  static const int minLength = 16;
  static const int maxLength = 200;
  static final RegExp _allowed = RegExp(r'^[A-Za-z0-9_\-]+$');

  final KeyValueSecretStore _store;

  Future<String?> read(AiProvider provider) async {
    if (!provider.isOnline) {
      return null;
    }
    try {
      return await _store.read(AiConfig.storeKeyFor(provider));
    } on Object {
      // Platform store unavailable (test/locked device) = key nahi, crash nahi।
      return null;
    }
  }

  /// Returns null on success, वरना user-facing (Hindi) error message — kuch
  /// save hi nahi hotा jab tak valid na हो।
  Future<String?> save(AiProvider provider, String rawKey) async {
    final String key = rawKey.trim();
    final String? error = validate(key);
    if (error != null) {
      return error;
    }
    if (!provider.isOnline) {
      return 'पहले Settings में कोई online provider चुनें, फिर key सेव होगी।';
    }
    try {
      await _store.write(AiConfig.storeKeyFor(provider), key);
      return null;
    } on Object {
      return 'Key इस फ़ोन की secure storage में सेव नहीं हो पाई।';
    }
  }

  /// true = key sach me मिटा दी गई। false = दिक्कत — UI तब झूठा "मिटा दिया"
  /// नहीं कहता, बल्कि असली बात बताता है।
  Future<bool> clear(AiProvider provider) async {
    try {
      await _store.delete(AiConfig.storeKeyFor(provider));
      return true;
    } on Object {
      return false;
    }
  }

  /// Entry ko kachra (URL, paste-with-quotes, spaces) store karne se roکتा है।
  static String? validate(String key) {
    if (key.isEmpty) {
      return 'Key खाली है।';
    }
    if (key.length < minLength) {
      return 'Key बहुत छोटी है (${key.length} chars) — पूरी copy हुई है क्या?';
    }
    if (key.length > maxLength) {
      return 'Key $maxLength characters से लंबी है — गलती से पूरा URL/जवाब तो नहीं paste हो गया?';
    }
    if (key.toLowerCase().startsWith('http')) {
      return 'यह URL लग रहा है, API key नहीं। key aistudio.google.com/apikey से मिलती है।';
    }
    if (!_allowed.hasMatch(key)) {
      return 'Key में सिर्फ़ letters, numbers, - और _ होने चाहिए। कोष्ठक/स्पेस/URL हटाइए।';
    }
    return null;
  }
}
