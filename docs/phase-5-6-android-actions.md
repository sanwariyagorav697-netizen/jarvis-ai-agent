# Phase 5–6 design: Android system integration (abhi IMPLEMENT nahi hua)

> **यह document सिर्फ़ design है।** नीचे दिए गए tools/permissions अभी `lib/` में
> नहीं हैं, इसलिए कुछ भी "चलता है" नहीं कहा जा रहा। Phase 5–6 में जो भी बनेगा,
> उसका status इसी file के नीचे वाले 5-label matrix में honest तरीके से लिखा
> जाएगा (और `README.md` §1 में भी)।

## 0. Testing labels (हर feature के लिए यही 5 level)

| Label | मतलब |
|---|---|
| 1 | Implemented (code repo में, CI ने compile/analyze + unit test पास किया) |
| 2 | Tested successfully (आपके फ़ोन पर चलकर दिखा — यह सिर्फ़ आप verify कर सकते हैं) |
| 3 | Requires API credentials (जैसे Gemini key, Home Assistant token) |
| 4 | Requires external hardware (IR blaster, smart plug, Wi-Fi AC remote) |
| 5 | Not supported by Android (हम दावा नहीं करते) |

## 1. Layered design (जो अभी के code पर टिकेगा)

```
AssistantController.submitText
   ├── LocalRouter (offline intents)            ← तुरंत, free, device-only
   └── JarvisAgent (AI)  ── toolCalls ──► ToolRegistry.execute()
                                            ├── argument validation
                                            ├── requiresConfirmation → dialog
                                            └── JarvisTool.run()  ← यहीं Android छुआ जाता है
```

नए tools को **केवल** `lib/tools/` में `JarvisTool` subclass बनाकर जोड़ा जाएगा और
`lib/main.dart` के `ToolRegistry(<JarvisTool>[...])` में register होगा — AI को
उन्हें "बताने" के लिए कुछ और नहीं बदलना पड़ेगा, क्योंकि declarations registry से
ही बनते हैं (`functionDeclarations()`)।

## 2. Plugin/Intent plan (free, maintenance वाले packages)

| काम | तरीक़ा | Permission | Android की हद |
|---|---|---|---|
| Website खोलना, web search | `url_launcher` → `https://…`, `https://google.com/search?q=` | कोई नहीं | ✅ label 1–2 |
| Maps (जगह दिखाना/रास्ता) | `geo:` URI या `https://maps.google.com/?q=` | कोई नहीं | ✅ label 1–2 |
| Phone dial screen | `tel:+91…` (ACTION_DIAL) | कोई नहीं — call button दबाता **आप** हो | ✅ label 1–2 |
| सीधे call करना (button के बिना) | `CALL_PHONE` permission + `android.permission.CALL_PHONE` | runtime permission | 🟡 label 2 + Play policy declaration; default **बंद** रखेंगे |
| SMS लिखकर देना | `sms:` / ACTION_SENDTO (Messages app खुलेगा, भेजता आप) | कोई नहीं | ✅ label 1–2 |
| SMS अपने आप भेजना | `SEND_SMS` | — | ❌ label 5 (Play policy: सिर्फ़ default SMS app कर सकती है) — **नहीं करेंगे** |
| किसे-भी share करना (text/url) | `share_plus` (ACTION_SEND chooser) | कोई नहीं | ✅ label 1–2 |
| Specific app खोलना | package-targeted launch intent: `android_intent_plus` या छोटा Kotlin platform channel (`getLaunchIntentForPackage`) | कोई special permission नहीं, पर app visible होना चाहिए | 🟡 label 2; `<queries>` में package नाम लिखना पड़ सकता है |
| "सारे ऐप्स" की लिस्ट / कोई भी ऐप नाम से खोलना | `QUERY_ALL_PACKAGES` | — | ❌ label 5 (Play policy restricted) — instead: user Settings में 5–6 ऐप की allow-list बनाएगा, हम वही खोल पाएँगे |
| Wi-Fi / Bluetooth चालू-बंद करना | settings screen खोलना: `android.settings.WIFI_SETTINGS`, `android.settings.BLUETOOTH` | कोई नहीं | 🟡 toggle खुद = label 5 (Android 10+ `setWifiEnabled` deprecated; device-owner/root चाहिए) |
| Calendar में event | `ACTION_INSERT` + `CalendarContract.Events.CONTENT_URI` (editor खुला में prefilled) | कोई नहीं (user save करता है) | ✅ label 1–2 |
| Google Reminder / Task sync | कोई public API नहीं | — | ❌ label 5; in-app task list (already ✅) या calendar ही realistic |
| Flashlight | camera2 + `CAMERA` permission | runtime | 🟡 label 2 (plugin `torch_light`/camera) — Phase 8 का optional |
| Volume / brightness / airplane mode | system settings / `WRITE_SETTINGS` (user-grant only) | special | 🟡 केवल वो चीज़ें जो user-grant से हों; बाक़ी label 5 |

**कुल नियम:** कोई भी ऐसा काम जो दूसरे app का data पढ़े, background में चले, या
device-admin/restricted permission माँगे — वो scope में नहीं। Accessibility
service का इस्तेमाल **नहीं** होगा (यही UI automation के लिए दुर्व्यवहार होता है)।

## 3. `android/app/src/main/AndroidManifest.xml` में जो चाहिए होगा

```xml
<!-- अभी: RECORD_AUDIO + INTERNET (है) -->
<uses-permission android:name="android.permission.CALL_PHONE"/>   <!-- optional, default off -->
<queries>
  <intent><action android:name="android.intent.action.VIEW"/></intent>
  <intent><action android:name="android.intent.action.SEND"/></intent>
  <!-- specific apps allow-list करने पर यहाँ package डालेंगे -->
  <package android:name="com.whatsapp"/>
</queries>
```

`<queries>` के बिना Android 11+ पर package visibility नहीं मिलती — इसलिए
"जो ऐप खोलना है उसका नाम allow-list में" ही ईमानदार तरीक़ा है (ऊपर वाली
QUERY_ALL_PACKAGES वाली line की जगह)।

## 4. Confirmation flow (sensitive चीज़ों के लिए) — design

1. `JarvisTool.requiresConfirmation = true` (call, SMS-compose, share, app-open
   जिससे कोई message भेजा जाए, smart-home command)।
2. `ToolRegistry.execute(..., confirm:)` dialog दिखाती है; `false` =
   `ToolResult.denied(...)` और **कुछ नहीं चलता** (यह अभी से implemented +
   unit-tested है — `test/tool_registry_test.dart`, `test/agent_test.dart`)।
3. Controller dialog के लिए `BuildContext` चाहिए → `HomeScreen` में एक
   `ConfirmationHost` (या `navigatorKey`) से dialog show करेंगे; AI-turn और
   local-turn दोनों वही `confirm` handler इस्तेमाल करेंगे, इसलिए AI के जवाब पर
   **एक से ज़्यादा dialog नहीं** कूदेंगे (test में verify किया जा चुका:
   `asked == 1`)।
4. हर result का एक लाइन chat में जाता है: `toolName ✓` / `toolName ✗ कारण` —
   और TTS वही बोलता है जो tool ने सच में कहा।

## 5. Phase 6 से पहले तय करने वाली बातें (आपसे पूछा जाएगा)

- App allow-list में कौन-कौन से ऐप हों? (नाम + package)
- Call/SMS: सिर्फ़ dialer screen खोलनी है, या "सीधे dial कर" option भी चाहिए?
- Reminder: device calendar में `ACTION_INSERT` (user save करे) चलेगा, या
  in-app list ही काफ़ी है?
- Smart home (Phase 7): आपके पास Home Assistant server है, या सिर्फ़ IR-blaster
  वाला phone/remote, या कोई smart plug? — इनमें से कुछ के बिना AC/TV control
  label 4/5 पर ही रहेगा।
