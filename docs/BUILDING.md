# Building the apps

The platform runners (`android/`, `ios/`, `windows/`, `web/`, `macos/`, `linux/`)
are **already generated** in this repository. Nothing to scaffold — just install the
SDK for the target you want and build.

| Target | Artifact | Host OS | Extra requirements |
| --- | --- | --- | --- |
| Android | `.apk` / `.aab` | Windows / macOS / Linux | Flutter + JDK 17 + Android SDK 36 |
| Web | `build/web` | any | Flutter |
| Windows | `.exe` folder | Windows | Flutter + Visual Studio 2022 (Desktop C++) + **Developer Mode** |
| iOS | `.app` / `.ipa` | **macOS only** | Flutter + Xcode 16+ + CocoaPods + Apple signing |
| macOS | `.app` | macOS only | Flutter + Xcode |
| Linux | bundle | Linux | Flutter + clang/ninja/GTK |

Versions used to produce the bundled artifacts: **Flutter 3.47.7 / Dart 3.13.5**,
Android **compileSdk 36 / targetSdk 36**, AGP 9.1.0, Kotlin 2.4.0, JDK 17.

---

## Android

```bash
export JAVA_HOME=/path/to/jdk17
export ANDROID_HOME=/path/to/android-sdk
flutter pub get
flutter build apk --release            # universal APK
flutter build apk --release --split-per-abi   # arm64 / armv7 / x86_64
flutter build appbundle --release      # Play Store (.aab)
```

Already configured in the repo:

* `android/app/src/main/AndroidManifest.xml` — `CAMERA` permission, ML Kit OCR
  dependency metadata, Japanese app label.
* `android/app/build.gradle.kts` — `implementation("com.google.mlkit:text-recognition-japanese:16.0.1")`.
  The Flutter plugin declares script models as `compileOnly`, so the **app** must
  bundle the Japanese model (otherwise `TextRecognitionScript.japanese` crashes at runtime).
* `android/app/proguard-rules.pro` — R8 rules for the ML Kit script models
  (`-dontwarn` for Chinese/Devanagari/Korean, keep ML Kit classes).
  Without these, `minifyReleaseWithR8` fails with "Missing classes detected".

### Signing for release

The release build currently signs with the **debug keystore** so `flutter build apk`
works out of the box. For distribution:

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias upload
```

`android/key.properties` (never commit):

```properties
storeFile=../release.jks
storePassword=***
keyPassword=***
keyAlias=upload
```

then add a `release` signing config in `android/app/build.gradle.kts` and point
`buildTypes.release.signingConfig` at it.

---

## Web

```bash
flutter build web --release
```

Output: `build/web/` — serve over HTTP/HTTPS (`file://` will not work):

```bash
cd build/web && python -m http.server 8080
# or: npx serve build/web
```

Deploy the folder to Netlify / Vercel / Firebase Hosting / S3 + CloudFront.
The web build uses the browser's `getUserMedia` stream for live 1D barcode
scanning and OCR frame capture; `web/zxing.min.js` is bundled automatically.
OCR runs through the `ocr` edge function. Camera permission requires HTTPS (or
`localhost`); if access is denied, the scanner falls back to photo upload.

---

## Windows

Requirements:

1. **Visual Studio 2022** with the *Desktop development with C++* workload
   (MSVC, Windows 10/11 SDK, CMake).
2. **Developer Mode** enabled (Settings → System → For developers), otherwise
   Flutter stops with *“Building with plugins requires symlink support”* —
   plugin symlinks are used by `image_picker_windows`, `path_provider_windows`,
   `shared_preferences_windows`, etc.

```powershell
flutter config --enable-windows-desktop
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\` (exe + DLLs + `data\`).
Zip that folder to distribute.

---

## iOS

Requires macOS. On Windows there is no supported way to compile an iOS app.

```bash
sudo xcode-select --switch /Applications/Xcode.app
sudo gem install cocoapods
flutter pub get
cd ios && pod install && cd ..

# unsigned build (CI / archive inspection)
flutter build ios --release --no-codesign

# signed .ipa (needs an Apple Development certificate + provisioning profile)
flutter build ipa --release
```

Before building, set the deployment target to **iOS 15.5+** (ML Kit requirement)
in Xcode → Runner → General → Minimum Deployments, and in `ios/Podfile`:

```ruby
platform :ios, '15.5'
```

Permissions are already in `ios/Runner/Info.plist`
(`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
`NSPhotoLibraryAddUsageDescription`) and the display name is `レシート帳`.

---

## CI (no local toolchains)

`.github/workflows/build.yml` builds Android, Windows, iOS (unsigned) and Web on
GitHub runners and uploads them as artifacts:

* push a tag (`git tag v1.0.0 && git push --tags`), or
* Actions → **Build apps** → *Run workflow*.

Set `SUPABASE_URL` / `SUPABASE_ANON_KEY` as repository **secrets** to bake the
credentials in; otherwise the produced app will show the in-app 接続設定 screen.

### Publish this repo and run the build

```bash
git remote add origin https://github.com/<your-account>/receipt-tracker.git
git push -u origin main
```

Then on GitHub:

1. **Settings → Secrets and variables → Actions → New repository secret**
   * `SUPABASE_URL` — `https://xxxx.supabase.co`
   * `SUPABASE_ANON_KEY` — the anon / publishable key

   (Skippable — without them the app opens the in-app 接続設定 screen.)

2. **Actions → Build apps → Run workflow** (branch `main`).
3. Wait ~8–15 min, then download the artifacts from the run page:

   | Artifact | Contents |
   | --- | --- |
   | `android-apk` | `app-release.apk` (universal) |
   | `windows-desktop` | `receipt_tracker-windows.zip` (exe + DLLs + data) |
   | `ios-unsigned` | `receipt_tracker-ios-unsigned.zip` (`Runner.app`) |
   | `web` | static site for Netlify/Vercel/S3 |

   Sign the iOS `.app` with your Apple team in Xcode, or add a signing step
   (`flutter build ipa`) with certificates stored as secrets.

   With the `gh` CLI the same thing is:

   ```bash
   gh repo create receipt-tracker --private --source=. --push
   gh secret set SUPABASE_URL -b"https://xxxx.supabase.co"
   gh secret set SUPABASE_ANON_KEY -b"eyJhbGciOi..."
   gh workflow run build.yml
   gh run list --workflow=build.yml
   gh run download <run-id>
   ```

> The built APKs in `dist/android/` are intentionally **not committed**
> (the universal APK is 103 MB, above GitHub's 100 MB file limit). CI regenerates
> them, and local builds land in `build/app/outputs/flutter-apk/`.

> First push identity check: if git complains, set
> `git config user.name "Your Name"` and `git config user.email "you@example.com"`.
> The initial commit was created with a placeholder identity — you can amend it
> with `git commit --amend --reset-author --no-edit` after setting yours.

---

## Quick local verification

```bash
flutter pub get
flutter analyze          # 0 errors
flutter test             # 24 tests
flutter build web --release
```

---

## Why this machine could not produce Windows / iOS builds

* `flutter doctor` → Visual Studio is not installed; installing it (and enabling
  Developer Mode) requires an elevated/UAC prompt, unavailable in this session.
* iOS compilation requires macOS + Xcode; impossible on Windows.
* Android and Web were built successfully — see `dist/`.
