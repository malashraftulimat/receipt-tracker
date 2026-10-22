# Platform setup

The platform runners are already generated in this repository and the Firebase /
camera / ML Kit settings are already applied. Keep this file as a reference when
regenerating the projects.

---

## Firebase (Web / Android / iOS)

The config is hard-coded in `lib/core/config/firebase_config.dart` (project
`receipt-tracker-78d9f`). No setup screen or local mode is used. The only
optional `--dart-define` is `RECAPTCHA_V3_SITE_KEY` for App Check.

In the Firebase console:

1. **Authentication → Sign-in method → Email/Password** → enable.
2. **Firestore Database** → create the database.
3. Deploy [`firestore.rules`](../firestore.rules) (`firebase deploy --only firestore:rules`).
4. **Authentication → Settings → Authorized domains** → add the GitHub Pages
   hostname (for example `malashraftulimat.github.io`). `localhost` is already
   authorized.
5. **Gemini key** → set the `GEMINI_API_KEY` GitHub Actions secret. Pages
   passes it with `--dart-define=GEMINI_API_KEY=...`; the key is never committed
   or bundled. Restrict it to your web domains and the Generative Language API.
   If it is empty, the app shows "AI key missing" and uses on-device OCR. The
   app defaults to the stable `gemini-3.1-flash-lite` model and falls back
   through stable `gemini-3.5-flash-lite` / `gemini-3.6-flash` /
   `gemini-3.8-flash` models (see `AiReceiptOcrService`). Retired 2.0/1.5/2.5
   model names are not used.
6. **App Check** → register the web app and create a reCAPTCHA v3 site key. Pass
   it with `--dart-define=RECAPTCHA_V3_SITE_KEY=...` (or set the GitHub Actions
   secret) to activate App Check in release web builds. Debug web builds use the
   App Check debug provider. Enabling enforcement is optional; without a key the
   app still starts and AI falls back to local OCR.
7. For native builds, register Android / iOS apps in the Firebase project if you
   want platform-specific OAuth or messaging. Email/password + Firestore work
   with the hard-coded `FirebaseOptions`.

Firestore layout:

```
users/{userId}/receipts/{receiptId}   # header + embedded items + OCR text only (no photo)
users/{userId}/categories/{categoryId}
users/{userId}/budgets/{yyyy-MM}
```

No Cloud Functions, Firebase Storage, Blaze plan or credit card is required.
Receipt photos are never written to Firestore, shared_preferences, local files or
exports. Legacy `image_base64` fields in old documents are ignored.

---

## Android (`android/`)

`android/app/src/main/AndroidManifest.xml`

```xml
<manifest ...>
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />

    <application ...>
        <!-- ML Kit: let it download the Japanese model on first use -->
        <meta-data
            android:name="com.google.mlkit.vision.DEPENDENCIES"
            android:value="ocr" />
    </application>
</manifest>
```

`android/app/build.gradle.kts`

```kotlin
android {
    defaultConfig {
        minSdk = 24          // required by Firebase Auth / Firestore
        targetSdk = flutter.targetSdkVersion
    }
}
```

`minSdk < 24` fails with the current Firebase plugins. No `google-services.json`
is needed because `Firebase.initializeApp(options: ...)` is called with the
hard-coded config.

---

## iOS (`ios/`)

`ios/Runner/Info.plist`

```xml
<key>NSCameraUsageDescription</key>
<string>レシートのバーコードと文字を読み取るためにカメラを使用します。</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>選択したレシート画像を読み取るために写真へアクセスします。画像は保存されません。</string>
```

`ios/Podfile`

```ruby
platform :ios, '15.5'   # google_mlkit_text_recognition requires iOS 15.5+
```

---

## Web (`web/index.html`)

Camera access needs a **secure context**: serve over HTTPS (GitHub Pages,
Netlify, etc.) or `localhost`, otherwise `getUserMedia` is unavailable.

- Live barcode detection uses `mobile_scanner`'s HTML5/WebRTC backend.
- `web/zxing.min.js` is bundled locally (no CDN required).
- Primary extraction uses the **direct Google AI Studio / Gemini Flash API** with a JSON
  response schema. If it fails (offline / quota / error), OCR falls back to
  **Tesseract.js** (`web/tesseract.min.js` + WASM). The first fallback scan
  downloads worker/WASM/Japanese+English language data from the Tesseract.js CDN;
  the browser caches it afterwards.
- The web scanner applies high-resolution and continuous-focus constraints to
  the `MediaStreamTrack` behind `mobile_scanner`'s `<video>` when the browser
  supports them. Tap the preview to re-focus; on iOS Safari use the
  **「端末のカメラを使う」** button (`<input type=file capture=environment>`).
- Receipt photos are kept in memory only and are discarded after saving/leaving.

If camera permission is explicitly denied or unsupported, the scanner shows the
photo-upload fallback.

---

## Windows / macOS / Linux

- `image_picker` opens a native file dialog.
- ML Kit/Tesseract fallbacks are not wired for desktop. Gemini still works when
  online; otherwise manual entry and CSV export remain available.
- macOS: add camera/photo entitlements if you enable camera capture later.

```bash
flutter run -d windows
```

---

## Verify the setup

1. `flutter analyze --no-fatal-infos` and `flutter test`.
2. Open the app: it should show the Firebase login screen (no setup screen).
3. Sign up with an email/password.
4. Home → スキャン → scan a JAN-13 barcode: review opens with the barcode filled.
5. Photograph a receipt (`レシートを撮影して読み取る`): Gemini extracts
   merchant/date/total/tax/items; if AI is unavailable, ML Kit (mobile) or
   Tesseract.js (web) is used automatically.
6. Save, edit the category, add a note, and confirm dashboard/search/analytics.
7. Sign in on a second device: the same receipts, items and budgets sync. Photos
   are never uploaded.
