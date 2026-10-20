# Platform setup

The platform runners are already generated in this repository and the Firebase /
camera / ML Kit settings are already applied. Keep this file as a reference when
regenerating the projects.

---

## Firebase (Web / Android / iOS)

The config is hard-coded in `lib/core/config/firebase_config.dart` (project
`receipt-tracker-78d9f`). No `--dart-define`, setup screen or local mode is used.

In the Firebase console:

1. **Authentication → Sign-in method → Email/Password** → enable.
2. **Firestore Database** → create the database.
3. Deploy [`firestore.rules`](../firestore.rules) (`firebase deploy --only firestore:rules`).
4. **Authentication → Settings → Authorized domains** → add the GitHub Pages
   hostname (for example `malashraftulimat.github.io`). `localhost` is already
   authorized.
5. For native builds, register Android / iOS apps in the Firebase project if you
   want platform-specific OAuth or messaging. Email/password + Firestore work
   with the hard-coded `FirebaseOptions`.

Firestore layout:

```
users/{userId}/receipts/{receiptId}   # header + embedded items + image_base64 + OCR text
users/{userId}/categories/{categoryId}
users/{userId}/budgets/{yyyy-MM}
```

No Cloud Functions, Firebase Storage, Blaze plan or credit card is required.

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
<string>保存済みのレシート画像を読み取るために写真へアクセスします。</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>撮影したレシート画像を保存します。</string>
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
- OCR uses **Tesseract.js** (`web/tesseract.min.js` + WASM). The first scan
  downloads worker/WASM/Japanese+English language data from the Tesseract.js CDN;
  the browser caches it afterwards.
- Receipt photos are compressed client-side and stored as base64 in Firestore.

If camera permission is explicitly denied or unsupported, the scanner shows the
photo-upload fallback.

---

## Windows / macOS / Linux

- `image_picker` opens a native file dialog.
- ML Kit/Tesseract are not wired for desktop; OCR is unavailable there.
  Manual entry and CSV export still work.
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
5. Photograph a receipt (`レシートを撮影して読み取る`): merchant/date/total/tax/items
   are prefilled by ML Kit (mobile) or Tesseract.js (web).
6. Save, edit the category, add a note, and confirm dashboard/search/analytics.
7. Sign in on a second device: the same receipts, items, budgets and images sync.
