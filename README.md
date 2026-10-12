# JARVIS — Android voice AI assistant

एक असली (non-demo) voice-enabled personal assistant for Android: Flutter app,
on-device speech recognition + text-to-speech, validated tool registry, और
Phase 4 में online AI (Google Gemini)।

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
| Online AI (Gemini) + API key in secure storage | ⏳ Phase 4 | — |
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
│   │   ├── settings_service.dart     # preferences
│   │   └── memory_service.dart       # history + tasks (device-only)
│   ├── tools/                        # current_time_tool, task_tools
│   └── widgets/                      # jarvis_orb, chat_bubble, status_strip
├── test/                             # unit tests (CI inhe fail होने पर रोकता है)
└── pubspec.yaml
```

Phase 4 में जुड़ेंगे: `lib/services/ai_service.dart`, `gemini_service.dart`,
`api_key_store.dart` (secure storage) और ज़रूरत पड़ने पर `backend/`.

---

## 3. APK बनाना और install करना (सिर्फ़ फ़ोन से)

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

Key banane के लिए: `https://aistudio.google.com/apikey` (Chrome → Desktop site)।

## 6. Data, permissions, security notes

- अभी app **कोई network request नहीं भेजता** — समय/तारीख़ और task list device पर
  बनते हैं। Settings में हर जवाब का source label दिखता है (डिवाइस / ऑनलाइन मॉडल)।
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
  `android/app/build.gradle.kts` me humne kuch set nahi kiya. Kisi plugin ke liye
  extra keep-rules chahiye ho to `android/app/proguard-rules.pro` bana dein —
  Flutter use automatically utha leta hai।
- APK ~20 MB hai kyunki ek "fat" APK me teeno ABI (armeabi-v7a, arm64, x86_64)
  hain. `flutter build apk --release --split-per-abi` se ~7 MB per-ABI files
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
4. ⏳ Gemini (ya Groq) + tool-calling + secure key + real error handling
5. ✅ Time/date tool + validated tool registry (Phase 2–3 के साथ ही)
6. ⏳ Supported Android actions (open app, dialer, share, calendar reminder)
7. ⏳ Smart-home layer (Home Assistant / IR bridge / compatible devices only)
8. ⏳ Format gate blocking + integration test + signed release uploads

## 9. "JARVIS" नाम के बारे में

नाम inspiration के लिए है। कोई Marvel asset, audio, या artwork copy नहीं किया —
सारा UI/colors/code original हैं। Ise "official JARVIS" mat kehिएगा।
