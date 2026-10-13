import 'ai_service.dart';
import 'gemini_service.dart';
import 'openai_compat_service.dart';

/// AI provider selection. Sirf ek jagah se badalta है — app rebuild zaroori
/// nahi (Settings screen isi ko save करती है)।
enum AiProvider {
  /// Online AI band; sirf device tools + local router चलेंगे।
  off,

  /// Google AI Studio (free tier, Flash/Flash-Lite)।
  gemini,

  /// Koi bhi OpenAI-compatible endpoint: Groq, OpenRouter, या hamara backend।
  openaiCompatible,
}

extension AiProviderLabel on AiProvider {
  String get label => switch (this) {
        AiProvider.off => 'बंद (सिर्फ़ डिवाइस टूल)',
        AiProvider.gemini => 'Google Gemini (AI Studio)',
        AiProvider.openaiCompatible => 'OpenAI-compatible (Groq/OpenRouter/backend)',
      };

  bool get isOnline => this != AiProvider.off;

  static AiProvider fromName(String? name) => AiProvider.values.firstWhere(
        (AiProvider p) => p.name == name,
        orElse: () => AiProvider.off,
      );
}

abstract final class AiConfig {
  /// Provider ke hisaab se default model।
  static String defaultModelFor(AiProvider provider) => switch (provider) {
        AiProvider.gemini => GeminiService.defaultModel,
        AiProvider.openaiCompatible => 'llama-3.1-8b-instant',
        AiProvider.off => '',
      };

  static String defaultBaseUrlFor(AiProvider provider) => switch (provider) {
        AiProvider.gemini => GeminiService.defaultBaseUrl,
        AiProvider.openaiCompatible => OpenAiCompatService.defaultBaseUrl,
        AiProvider.off => '',
      };

  /// Key ko kis store-key me rakha जाए (provider-wise, taaki ek provider बदलने
  /// पर दूसरे की key गलती से use/leak न हो)।
  static String storeKeyFor(AiProvider provider) => 'jarvis.ai_key.${provider.name}';
}

abstract final class AiServiceFactory {
  /// [apiKey] null/false hone par service null — controller tab local router +
  /// honest "AI configure nahi hai" use करता है (कभी fake jawab नहीं)।
  static AiService? build({
    required AiProvider provider,
    required String model,
    required String baseUrl,
    required String? apiKey,
  }) {
    if (!provider.isOnline) {
      return null;
    }
    final String trimmedModel = model.trim().isEmpty
        ? AiConfig.defaultModelFor(provider)
        : model.trim();
    final String trimmedBase = baseUrl.trim().isEmpty
        ? AiConfig.defaultBaseUrlFor(provider)
        : baseUrl.trim();
    final String? key = apiKey?.trim();

    if (provider == AiProvider.gemini) {
      return GeminiService(model: trimmedModel, apiKey: key, baseUrl: trimmedBase);
    }
    return OpenAiCompatService(
      model: trimmedModel,
      apiKey: key,
      baseUrl: trimmedBase,
    );
  }
}
