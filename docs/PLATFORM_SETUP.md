# Platform setup

The platform runners are already generated in this repository **and the settings
below are already applied** (Android manifest/ML Kit, iOS Info.plist). Keep this
file as a reference when regenerating the projects, then re-apply the changes.

---

## Android (`android/`)

`android/app/src/main/AndroidManifest.xml`

```xml
<manifest ...>
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

`android/app/build.gradle`

```gradle
android {
    compileSdk 34
    defaultConfig {
        minSdk 21          // required by mobile_scanner & ML Kit
        targetSdk 34
        multiDexEnabled true
    }
}
```

If you build with `minSdk < 21` the build fails in `mobile_scanner` / ML Kit.

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

No permissions block is required for the file picker. If you later enable
`mobile_scanner` on web, serve the app over HTTPS (or `localhost`) so `getUserMedia`
works.

Supabase Storage must allow your origin — the default `*` CORS policy works, but you
can restrict it in *Project Settings → API → CORS*.

> Web uses the `ocr` **Edge Function**. Without `GOOGLE_VISION_API_KEY` the review
> screen simply opens with empty fields and a warning — manual entry still works.

---

## Windows / macOS / Linux

- `image_picker` opens a native file dialog (`ImageSource.gallery`).
- ML Kit is unavailable, so OCR goes through the `ocr` Edge Function.
- macOS: add camera/photo entitlements if you enable camera capture later
  (`macos/Runner/*.entitlements`).

```bash
flutter run -d windows --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

---

## Supabase edge function

```bash
supabase login
supabase link --project-ref <project-ref>
supabase functions deploy ocr
supabase secrets set GOOGLE_VISION_API_KEY=<your-key>
```

`supabase/functions/ocr/index.ts` verifies the caller's JWT with the anon key and the
user's `Authorization` header, then calls Vision `TEXT_DETECTION` with
`languageHints: ['ja', 'en']`.

---

## Verify the setup

1. `flutter test` — parser & formatter unit tests pass.
2. Sign up with an email/password on the auth screen.
3. Home → スキャン → scan any JAN-13 barcode: review opens with the barcode filled in.
4. Photograph a receipt (`レシートを撮影して読み取る`): merchant / date / total / tax are
   prefilled.
5. Save, then edit the category, add a note, and confirm the dashboard grouping,
   search, filters and charts update.
6. Sign in on a second device — the same receipts and images appear.
