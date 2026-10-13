import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_ai_agent/services/ai/ai_config.dart';
import 'package:jarvis_ai_agent/services/ai/ai_service.dart';
import 'package:jarvis_ai_agent/services/ai/api_key_store.dart';
import 'package:jarvis_ai_agent/services/ai/gemini_service.dart';
import 'package:jarvis_ai_agent/services/ai/openai_compat_service.dart';

/// In-memory fake — test environment me platform channel नहीं चलता, इसलिए
/// storage का contract ही verify करते हैं (क्या लिखा, क्या पढ़ा, क्या मिटा)।
class _FakeSecretStore implements KeyValueSecretStore {
  final Map<String, String> saved = <String, String>{};
  bool failNextWrite = false;

  @override
  Future<String?> read(String key) async => saved[key];

  @override
  Future<void> write(String key, String value) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('keystore locked');
    }
    saved[key] = value;
  }

  @override
  Future<void> delete(String key) async => saved.remove(key);
}

void main() {
  group('ApiKeyStore.validate', () {
    test('valid Gemini-style key pass hotी है', () {
      const String key = 'AIzaSyD-abcdefghij0123456789_KLMNOPQRSTU';
      expect(JarvisApiKeyStore.validate(key), isNull);
    });

    test('छोटी / बड़ी / खाली key reject', () {
      expect(JarvisApiKeyStore.validate(''), contains('खाली'));
      expect(JarvisApiKeyStore.validate('AIza123'), contains('छोटी'));
      expect(JarvisApiKeyStore.validate('a' * 250), contains('लंबी'));
    });

    test('spaces / quotes / URL वाली key reject (गलत paste)', () {
      expect(JarvisApiKeyStore.validate('AIza abcd efgh ijkl mnop'), contains('letters'));
      expect(JarvisApiKeyStore.validate('"AIzaSyDabcdefghij0123456789"'), contains('letters'));
      expect(
        JarvisApiKeyStore.validate('https://aistudio.google.com/apikey'),
        contains('URL'),
      );
    });
  });

  group('JarvisApiKeyStore', () {
    late _FakeSecretStore store;
    late JarvisApiKeyStore keys;

    setUp(() {
      store = _FakeSecretStore();
      keys = JarvisApiKeyStore(store: store);
    });

    test('save के बाद read वही key देता है (store-key provider के नाम से)', () async {
      const String key = 'AIzaSyD-abcdefghij0123456789_KLMNOPQRSTU';
      expect(await keys.save(AiProvider.gemini, '  $key  '), isNull);
      expect(store.saved.keys.single, 'jarvis.ai_key.gemini');
      expect(await keys.read(AiProvider.gemini), key);
    });

    test('हर provider की key अलग रहती है (cross-provider leak नहीं)', () async {
      await keys.save(AiProvider.gemini, 'AIzaSyD-abcdefghij0123456789_KLMNOPQRSTU');
      await keys.save(
        AiProvider.openaiCompatible,
        'gsk_abcdefghijklmnopqrstuvwxyz0123456789',
      );
      expect(store.saved.length, 2);
      expect(await keys.read(AiProvider.gemini), startsWith('AIza'));
      expect(await keys.read(AiProvider.openaiCompatible), startsWith('gsk_'));
    });

    test('invalid key पर कुछ सेव नहीं होता, error लौटता है', () async {
      final String? error = await keys.save(AiProvider.gemini, 'nope');
      expect(error, contains('छोटी'));
      expect(store.saved, isEmpty);
      expect(await keys.read(AiProvider.gemini), isNull);
    });

    test('provider off हो तो read null और save मना करता है', () async {
      expect(await keys.read(AiProvider.off), isNull);
      expect(
        await keys.save(AiProvider.off, 'AIzaSyD-abcdefghij0123456789_KLMNOPQRSTU'),
        contains('provider'),
      );
    });

    test('clear सच में मिटाता है और true लौटाता है', () async {
      await keys.save(AiProvider.gemini, 'AIzaSyD-abcdefghij0123456789_KLMNOPQRSTU');
      expect(await keys.clear(AiProvider.gemini), isTrue);
      expect(store.saved, isEmpty);
      expect(await keys.read(AiProvider.gemini), isNull);
    });

    test('write fail होने पर save झूठा "सेव हो गई" नहीं कहता', () async {
      store.failNextWrite = true;
      expect(
        await keys.save(AiProvider.gemini, 'AIzaSyD-abcdefghij0123456789_KLMNOPQRSTU'),
        contains('सेव नहीं हो पाई'),
      );
    });

    test('store read fail करे to key null (crash नहीं) — offline/locked device', () async {
      final JarvisApiKeyStore broken = JarvisApiKeyStore(store: _ThrowingStore());
      expect(await broken.read(AiProvider.gemini), isNull);
    });
  });

  group('AiConfig / AiProvider', () {
    test('provider name से round-trip; अजनबी name = off', () {
      expect(AiProviderLabel.fromName('gemini'), AiProvider.gemini);
      expect(AiProviderLabel.fromName('openaiCompatible'), AiProvider.openaiCompatible);
      expect(AiProviderLabel.fromName(null), AiProvider.off);
      expect(AiProviderLabel.fromName('claude'), AiProvider.off);
    });

    test('off के लिए कोई default model/base URL नहीं', () {
      expect(AiConfig.defaultModelFor(AiProvider.off), '');
      expect(AiConfig.defaultBaseUrlFor(AiProvider.off), '');
      expect(AiConfig.defaultModelFor(AiProvider.gemini), 'gemini-3.1-flash-lite');
      expect(
        AiConfig.defaultBaseUrlFor(AiProvider.openaiCompatible),
        startsWith('https://'),
      );
    });

    test(' बिना key के factory null देता है (fake jawab कभी नहीं)', () {
      expect(
        AiServiceFactory.build(
          provider: AiProvider.off,
          model: '',
          baseUrl: '',
          apiKey: null,
        ),
        isNull,
      );
      final AiService? noKey = AiServiceFactory.build(
        provider: AiProvider.gemini,
        model: '',
        baseUrl: '',
        apiKey: '   ',
      );
      expect(noKey, isNotNull);
      expect(noKey!.isConfigured, isFalse);
      noKey.dispose();
    });

    test('model/baseUrl खाली हो तो default भर जाते हैं, trimmed value रहती है', () {
      final GeminiService gemini = AiServiceFactory.build(
        provider: AiProvider.gemini,
        model: '',
        baseUrl: '',
        apiKey: ' AIzaSyD-abcdefghij0123456789_KLMNOPQRSTU ',
      )! as GeminiService;
      expect(gemini.model, 'gemini-3.1-flash-lite');
      expect(gemini.baseUrl, 'https://generativelanguage.googleapis.com');
      expect(gemini.label, contains('Gemini'));
      gemini.dispose();

      final OpenAiCompatService openai = AiServiceFactory.build(
        provider: AiProvider.openaiCompatible,
        model: ' my-model ',
        baseUrl: 'https://example.com/v1 ',
        apiKey: 'sk-or-abcdefghijklmnopqrstuvwxyz012345',
      )! as OpenAiCompatService;
      expect(openai.model, 'my-model');
      expect(openai.baseUrl, 'https://example.com/v1');
      expect(openai.endpoint.toString(), 'https://example.com/v1/chat/completions');
      openai.dispose();
    });
  });
}

class _ThrowingStore implements KeyValueSecretStore {
  @override
  Future<String?> read(String key) async => throw StateError('unavailable');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('unavailable');

  @override
  Future<void> delete(String key) async => throw StateError('unavailable');
}
