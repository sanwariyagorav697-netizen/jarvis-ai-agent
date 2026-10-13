# JARVIS — Android voice AI assistant

एक असली (non-demo) voice-enabled personal assistant for Android: Flutter app,
on-device speech recognition + text-to-speech, validated tool registry, और
online AI (Google Gemini या कोई भी OpenAI-compatible endpoint) — API key सिर्फ़
आपके फ़ोन की secure storage में।

**यह project एक फ़ोन से ही बनता है।** कोई PC/laptop ज़रूरी नहीं: code GitHub पर
रहता है, APK GitHub Actions बनाता है, और आप वही artifact install करते हैं।

---

## 1. अभी क्या-क्या चलता है (state matrix)

| Feature | Status | कैसे verify किया |
|---|---|---|
| Flutter project repo में (`lib/`, `android/`, `pubspec.yaml`) | ✅ Implemented | CI structure check step |
| Release APK build via GitHub Actions | ✅ Implemented | Actions run का artifact |
| Mic से सुनना (Android SpeechRecognizer), हिंदी + English | 🟡 Implemented — device पर test बाकी | `flutter test` सिर्फ़ error-mapping verify करता है |
| बोलकर जवाब (Android TTS, `hi-IN`) | 🟡 Implemented — device पर test बाकी | Settings → "आवाज़ टेस्ट करें" |
| समय + तारीख़ टूल (device clock, real) | ✅ Implemented + unit tested | `test/current_time_tool_test.dart` |
| In-app कामों की लिस्ट (add/list/complete) | ✅ Implemented + unit tested | `test/local_router_test.dart` |
| Tool registry: validation, permission/confirmation, real success/failure | ✅ Implemented + unit tested | `test/tool_registry_test.dart` |
| Conversation memory (device पर, on/off + erase) | ✅ Implemented + unit tested | `test/memory_service_test.dart` |
| JARVIS HUD UI (animated orb, state chips) | ✅ Implemented | manual |
| Online AI: Gemini + OpenAI-compatible, tool-calling (model टूल माँगता है, registry चलाती है) | 🟡 Implemented + unit tested — फ़ोन पर असली key से test बाकी | `test/gemini_service_test.dart`, `test/openai_compat_service_test.dart`, `test/agent_test.dart` |
| API key: Android Keystore-backed secure storage + "Test API Connection" | 🟡 Implemented + unit tested — फ़ोन पर test बाकी | `test/api_key_store_test.dart`; फ़ोन: Settings → Test API Connection |
| API errors के Hindi संदेश (429 RPM / daily quota / galat key / 404 model / timeout / offline) | ✅ Implemented + unit tested | `test/ai_service_test.dart` |
| ऐप्स खोलना, dialer, share, settings screens | ⏳ Phase 6 | — |
| Android calendar/reminders में real reminder | ⏳ Phase 6 | — |
| AC/TV/smart-home control | ⏳ Phase 7 — **external hardware/API ज़रूरी** | — |
| "हर ऐप/सेटिंग का कंट्रोल" | ❌ Android allow नहीं करता | — |
| हमेशा-सुनने वाला wake word (app बंद होने पर) | ❌ Android background/battery restrictions के कारण भरोसेमंद नहीं | — |

Status legend: ✅ implemented + tested · 🟡 implemented, device-test pending ·
⏳ आगे के phase · ❌ not supported.

**कोई भी fake success यहाँ नहीं है:** tool जो असफल होता है, वही दिखता है (✗ +
लाल), और जो feature अभी बना नहीं, वो "abhi nahi" बोलता है — नक़ल नहीं करता।

---

## 2. Repo structure

```
jarvis-ai-agent/
├── .github/workflows/build-apk.yml   # सारा build + tests + APK artifact
├── android/                          # Flutter 3.47.7 के template से बना असली scaffold
│   ├── app/build.gradle.kts          # package id + signing (key.properties)
│   ├── app/proguard-rules.pro        # R8 keep rules (flutter_secure_storage) — release APK के लिए ज़रूरी
│   ├── app/src/main/AndroidManifest.xml  # permissions + <queries>
│   └── gradle/wrapper/               # wrapper jar/gradlew CI में Flutter tool inject करता है
├── lib/
│   ├── main.dart                     # composition root
│   ├── app/                          # theme (Material 3, dark HUD)
│   ├── models/                       # chat message, tool result, task, status
│   ├── screens/                      # home (chat+mic), settings
│   ├── services/
│   │   ├── assistant_controller.dart # state machine: mic → router → tools → TTS
│   │   ├── voice_service.dart        # SpeechRecognizer wrapper + error mapping
│   │   ├── tts_service.dart          # TextToSpeech wrapper (stop/repeat/await)
│   │   ├── tool_registry.dart        # validation + confirmation + execution
│   │   ├── local_router.dart         # offline intent matching (AI नहीं, fallback)
│   │   ├── settings_service.dart     # preferences (AI provider/model/baseUrl; key यहाँ नहीं)
│   │   ├── memory_service.dart       # history + tasks (device-only)
│   │   └── ai/                       # online AI layer (Phase 4)
│   │       ├── ai_service.dart       # provider-independent contract + HTTP→Hindi error mapping
│   │       ├── gemini_service.dart   # Gemini REST (generateContent + function calling)
│   │       ├── openai_compat_service.dart  # Groq/OpenRouter/self-host backend, same contract
│   │       ├── jarvis_agent.dart     # tool round-trip loop (max 3 rounds), honest failures
│   │       ├── api_key_store.dart    # secure storage + key entry validation
│   │       ├── ai_config.dart        # provider enum + defaults + service factory
│   │       └── jarvis_persona.dart   # system prompt + device context (date/time guess न करे)
│   ├── tools/                        # current_time_tool, task_tools
│   └── widgets/                      # jarvis_orb, chat_bubble, status_strip
├── test/                             # unit tests (CI inhe fail होने पर रोकता है)
└── pubspec.yaml
```

AI layer `lib/services/ai/` में है (ऊपर की tree देखें)। `backend/` जान-बूझकर
अभी नहीं है: free Python hosts 15 मिनट में so जाते हैं, और voice assistant के
लिए वो UX बर्बादी है — इसलिए key on-device secure storage में है (v1 decision)।
अपना backend जोड़ना हो तो Settings → Base URL से `baseUrl` बदलिए, code नहीं।

---

## 3. APK बनाना और install करना (सिर्फ़ फ़ोन से)

### सबसे आसान तरीक़ा: Release का direct link (GitHub login भी ज़रूरी नहीं)

**Releases** page → latest release (जैसे `v1.0.0-phase4`) → **`jarvis-release.apk`** पर tap →
download → open → "unknown sources" allow → **Install**। साथ में `jarvis-release.apk.sha256.txt`
है (मिलाने के लिए)। Release asset permanent रहता है और बिना-login download होता है; जबकि Actions
का artifact 30 दिन में expire हो जाता है और उसे download करने के लिए sign-in चाहिए।

Release कैसे बनता है: आप `v1.0.1` जैसा **tag** बनाइए (repo → Tags → *Create new tag*, desktop site
पर) → CI अपने-आप build + tests चलाता है, सब हरा होने पर `release` job APK ko us tag ke Release par
daal deta hai। नीचे के artifact steps tab भी काम करेंगे (एक ही APK है)।

### Actions artifact से (agar release na bana ho)

1. Chrome (⋮ → **Desktop site**) → `https://github.com/<aapka-username>/jarvis-ai-agent/actions`
2. **Run workflow** → **Run workflow** button → done. (Push पर अपने-आप भी चलता है।)
3. ~4–6 मिनट रुकें। हरा ✓ दिखे।
4. उसी run में नीचे **Artifacts** → `jarvis-ai-agent-apk` → download (ZIP)।
5. ZIP को **ZArchiver** (Play Store, free) या Files से निकालें → अंदर `.apk`।
6. APK पर tap → "unknown sources" allow → **Install**।
7. Install होते ही Settings → permissions → **Microphone** allow करें।

Build fail हो? Actions खुद एक **issue** खोलता है जिसमें error का आख़िरी हिस्सा
हिंदी-पठनीय form में होता है — उसे फ़ोन पर पढ़ें।

## 4. Signing और upgrade compatibility (ज़रूरी)

- `android/app/build.gradle.kts` में package id है **`com.jarvis.assistant`**।
  इसे बदलना = नया ऐप (पुराना delete नहीं होगा, दो ऐप दिखेंगे)। इसलिए पहली बार
  में ही सही रखा गया है — पुराना `com.example.jarvis_ai_agent` वाला build अलग ऐप था।
- Keystore के बिना build **debug key** से sign होता है। GitHub का runner हर build
  पर नया debug key बनाता है → **दूसरा APK पुराने के ऊपर install नहीं होगा**
  (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`); पहले uninstall करना पड़ेगा।
- एक बार proper keystore बना लें, फिर upgrades बिना uninstall के होंगे:
  1. Play Store से **Termux** install करें (free)।
  2. Termux में (एक बार): `pkg install openjdk-17 && termux-setup-storage`
  3. `keytool -genkeypair -v -keystore jarvis.jks -alias jarvis -keyalg RSA -keysize 2048 -validity 10000`
     → password सिर्फ़ अपने पास रखें (GitHub पर कहीं **न** लिखें)।
  4. `base64 jarvis.jks > jarvis.b64` → फ़ाइल `Downloads/` में मिलेगी
     (`cp jarvis.jks /sdcard/Download/`), उसे खोलकर पूरा content copy करें।
  5. GitHub repo → **Settings → Secrets and variables → Actions → New repository
     secret**, 4 secrets बनाएँ: `JARVIS_KEYSTORE_BASE64` (b64 content),
     `JARVIS_KEYSTORE_PASSWORD`, `JARVIS_KEY_ALIAS` = `jarvis`, `JARVIS_KEY_PASSWORD`।
  6. अगला build अपने-आप उसी key से sign होगा (workflow का
     "Set up release signing" step)।

`.jks`, `.keystore` और `key.properties` git में नहीं जाते (`.gitignore` देखें)।

## 5. AI provider (Phase 4) — कौनसी free service

- **Primary: Google AI Studio / Gemini API free tier.** Card ज़रूरी नहीं।
  2026 से free tier पर सिर्फ़ Flash/Flash-Lite models हैं (Pro हटा दिए गए),
  live RPM/TPM/RPD limits आपके project के हिसाब से AI Studio में दिखती हैं:
  <https://aistudio.google.com/rate-limit> — typical: 5–15 requests/min,
  ~250–1000 requests/day, रोज़ midnight Pacific पर reset।
  ⚠️ Free tier पर Google inputs को product improvement के लिए use **कर सकता है**।
- **Fallback: Groq free** (~30 RPM / ~1000 RPD, no training on prompts) —
  OpenAI-compatible होने की वजह से sirf config बदलकर switch होगा।
- Kuch bhi unlimited नहीं। 429/quota/offline को app अलग-अलग Hindi message से
  handle करेगा (retry + "आज का quota खत्म, xx बजे reset")।
- Key का storage: **app की Settings से → Android Keystore-backed secure
  storage**. Key git, APK assets, GitHub comments या किसी public file में नहीं।
  v1 में कोई backend नहीं (free FastAPI hosts 15 मिनट में so जाते हैं — voice
  assistant के लिए वो UX बर्बाद है)। Backend चाहिए तो Phase 4b में `baseUrl`
  बदलकर जोड़ दिया जाएगा।

### Phase 4 चालू करने के 6 कदम (सिर्फ़ फ़ोन से)

1. **Key बनाइए:** Chrome → *Desktop site* → <https://aistudio.google.com/apikey>
   → "Create API key" → key copy कीजिए (यह key कहीं share/mat कीजिएगा)।
2. **APK install** कीजिए (Actions artifact से — §3 देखें)।
3. **Settings → "ऑनलाइन AI"** → provider *Google Gemini* चुनिए।
4. **मॉडल:** खाली छोड़ दें तो default `gemini-3.1-flash-lite` (free tier पर
   उपलब्ध)। नीचे दिए chips से `gemini-3.5-flash`/`gemini-2.5-flash` भी चुन
   सकते हैं — Google model के नाम बदलता रहता है, इसलिए field editable है।
5. **API key** paste करके **Save key** दबाइए। key तुरंत secure storage में जाती
   है, text box clear हो जाता है, और UI सिर्फ़ आख़िरी 4 characters दिखाता है।
6. **Test API Connection** दबाइए — यह *सच में* एक छोटी API call करता है और
   latency + नमूना जवाब दिखाता है। ✓ आया = सब ठीक; ✗ आया = संदेश बताएगा कि
   key गलत है, model उपलब्ध नहीं है, या quota भर गया है।

### Provider के option

- **Gemini (default):** ऊपर बताया गया free tier। ⚠️ free tier पर Google inputs
  को product improvement के लिए use **कर सकता है** — संवेदनशील बात न लिखें।
- **OpenAI-compatible (Groq / OpenRouter / अपना backend):** provider
  *OpenAI-compatible* चुनिए, Base URL chip दबाइए (Groq =
  `https://api.groq.com/openai/v1`), और उस endpoint की model name डालिए।
  Groq free tier ~30 RPM / ~1000 RPD और prompts पर training नहीं करता।
- **बंद (default setting):** provider `off` = कोई network call नहीं, सिर्फ़
  device tools। AI configure न होने पर app "नकली" जवाब कभी नहीं देता — सीधे
  कहता है कि Settings में key डालिए।

### ज़रूरी design notes (code में भी यही है)

- समय/तारीख़ और कामों के हुक्म **पहले local router** से चलते हैं (instant,
  offline, free quota बचता है)। बाकी सब AI के पास जाता है, और AI भी **वही**
  `ToolRegistry` इस्तेमाल करता है — यानी model का हर "कमांड" validation और
  confirmation से गुज़रता है, और max 3 tool rounds के बाद रुक जाता है।
- `temperature`/`thinkingConfig` जान-बूझकर नहीं भेजे जाते (Gemini 3 के thinking
  models कुछ values पर 400 देते हैं); सिर्फ़ `maxOutputTokens = 700`।
- 429 (प्रति-मिनट) पर **एक ही** automatic retry, और तभी जब server `Retry-After`
  में 12 सेकंड से कम bole। daily quota पर retry नहीं — झूटी उम्मीद नहीं देते।
- 25 सेकंड का hard timeout: नेट धीमा हो तो app टंगता नहीं, "टाइमआउट" संदेश आता है।

## 6. Data, permissions, security notes

- Provider **off** होने तक app कोई network request नहीं भेजता — समय/तारीख़ और
  task list device पर बनते हैं। Provider चालू करने पर सिर्फ़ आपका सवाल + थोड़ा
  device context (तारीख़/भाषा) HTTPS से चुने हुए provider जाता है; API key
  header में जाती है, URL/log में कभी नहीं। Settings में हर जवाब का source label
  दिखता है (डिवाइस / ऑनलाइन मॉडल / टूल)।
- Key `flutter_secure_storage` 11.x की default policy में रहती है: Android Keystore
  में protected RSA-OAEP(SHA-256) से wrapped key, value AES/GCM से encrypted — यानी
  plain `SharedPreferences` XML में key नहीं लिखी जाती। (v11 में
  `encryptedSharedPreferences` जैसा कोई flag बचा नहीं; default ही strong policy है —
  plugin के `lib/options/android_options.dart` से verify किया, 2026-10-13।)
  app uninstall = key भी गई; rooted device पर भी Keystore seed के बिना पढ़ना आसान
  नहीं। **ध्यान दें:** plugin का `resetOnError: true` default है — device का PIN/lock
  बदलने या factory reset के बाद Keystore key न मिले तो stored value अपने आप मिट
  जाएगी और Settings में key दोबारा डालनी पड़ेगी (designed behavior, bug नहीं)।
  conversation memory में password/API key/OTP कभी store नहीं की जाती (system prompt
  भी मना करता है)।
- Mic सिर्फ़ तब सुनता है जब आप माइक button दबाते हैं। App बंद होने पर कुछ सुनता
  नहीं है, और हम ये दावा नहीं करते। Wake word (Phase 6+) भी "jab app foreground
  me ho" तक सीमित रहेगा, क्योंकि Android background execution/battery
  optimization उसे भरोसेमंद नहीं रहने देता।
- Permissions सिर्फ़ दो: `RECORD_AUDIO`, `INTERNET`। Call/SMS ke liye
  `CALL_PHONE`/`SEND_SMS` **नहीं** maange gaye — wo system screens (dialer /
  share sheet) se, user-confirm karke honge। Accessibility service bilkul nahi।
- AI model ko kabhi shell/arbitrary code execute nahi karne dete: model sirf
  `{tool, arguments}` maangta hai, `ToolRegistry` validate + (sensitive hone par)
  confirm karke hi chalati hai।
- `pubspec.lock` commit nahi hai, isliye transitive dependency versions CI par
  resolve hote hain; direct deps pinned ranges par hain aur Flutter version
  workflow me pin hai (`3.47.7`)।
- R8 + resource shrinking: Flutter 3.47 ka apna Gradle plugin ise release build
  par khud on karta hai (aur `flutter_proguard_rules.pro` bhi deta hai), isliye
  `android/app/build.gradle.kts` me humne kuch set nahi kiya. Jo plugins reflection
  ya runtime class-lookup par chalte hain (`flutter_secure_storage` → Android
  Keystore / androidx.security) unke keep rules **`android/app/proguard-rules.pro`
  me pehle se likhe hain** — Flutter ye file apne aap add kar leta hai. In rules ke
  bina release APK me key save karte waqt crash ho sakta hai, jabki debug build me
  sab theek dikhta hai (isliye ye galti chup jati hai)।
- Release APK ≈49.6 MB (51,965,100 bytes) है, क्योंकि एक "fat" APK me teeno ABI
  (armeabi-v7a, arm64-v8a, x86_64) hoti hain. Actions ka artifact 24 MB dikhta hai
  kyonki GitHub ZIP compress karta hai — file size ka asli figure Release asset par
  hai. Mobile data par bhaari ho to Phase 8 me `flutter build apk --release
  --split-per-abi` option layenge (~7 MB per-ABI; aapke phone me aam taur par
  `arm64-v8a` chahiye)।
  milti hain (Phase 8 me option banayenge)।

## 7. Local dev / test (PC nahi chahiye)

Repo clone karke Termux + `flutter` SDK setup karna possible है, पर heavy है और
recommended नहीं। यही commands CI हर build par chalata है:

```
flutter pub get
dart format --output=none --set-exit-if-changed lib test   # abhi warning-only
flutter analyze                                             # blocking
flutter test                                                # blocking
flutter build apk --release
```

Naya test add karte waqt bas `test/` में फ़ाइल रखें — CI खुला चलाएगा।

## 8. Roadmap (phases)

1. ✅ Repo audit
2. ✅ Real Flutter project in git + CI builds APK from repo
3. ✅ Voice in/out + local tools + settings + memory
4. ✅ Code + tests + CI पूरे: `flutter analyze` 0 issues, 125 unit tests (mock HTTP से),
     release APK GitHub Actions पर बना — green run `38408702931`, artifact
     `jarvis-ai-agent-apk` (24,237,123 bytes).
   🟡 बचा सिर्फ़ label 2 का आख़िरी हिस्सा: आपके फ़ोन पर असली key से "Test API Connection"
     + असली conversation (label 3: needs your API credentials) — ऊपर §5 के 5 step करें।
5. ✅ Time/date tool + validated tool registry (Phase 2–3 के साथ ही)
6. ⏳ Supported Android actions (open app, dialer, share, calendar reminder)
7. ⏳ Smart-home layer (Home Assistant / IR bridge / compatible devices only)
8. ⏳ Format gate blocking + integration test + signed release uploads

## 9. "JARVIS" नाम के बारे में

नाम inspiration के लिए है। कोई Marvel asset, audio, या artwork copy नहीं किया —
सारा UI/colors/code original हैं। Ise "official JARVIS" mat kehिएगा।
