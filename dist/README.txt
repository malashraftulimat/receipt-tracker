レシート帳 v1.0.0 — built artifacts
===================================

Android (installable)
---------------------
dist/android/receipt_tracker-1.0.0-arm64-v8a.apk     <- ほとんどの実機 (64-bit ARM)
dist/android/receipt_tracker-1.0.0-armeabi-v7a.apk   <- 古い 32-bit ARM 端末
dist/android/receipt_tracker-1.0.0-x86_64.apk        <- エミュレータ / x86 タブレット
dist/android/receipt_tracker-1.0.0-universal.apk     <- 全 ABI 同梱 (どの端末でも可、大きい)

インストール:
  1. APK を端末へ転送 (USB / Google Drive / メール添付など)
  2. 「提供元不明のアプリ」を許可してインストール
  3. 署名はデバッグ鍵です。Play Store 配布時は release keystore で再署名してください
     (docs/BUILDING.md 参照)。

Web (PWA)
---------
dist/receipt_tracker-1.0.0-web.zip
  - 展開して HTTPS サーバーで配信してください (file:// では動きません)
    python -m http.server 8080   ->  http://localhost:8080
    npx serve .
  - Netlify / Vercel / Firebase Hosting / GitHub Pages にそのまま置けます。
  - カメラのライブスキャンは非対応。画像を選択 → サーバーOCR になります。

iOS / Windows
-------------
このマシンではビルドできません (iOS = macOS + Xcode 必須、
Windows = Visual Studio C++ + Developer Mode 必須)。
ソースは同梱済みなので、次のどちらかで生成できます:
  * .github/workflows/build.yml を GitHub で実行 (iOS .app / Windows .zip を artifact で取得)
  * macOS / Windows 実機で docs/BUILDING.md の手順を実行

初回起動時の接続設定
--------------------
どのビルドも初回に「接続設定」画面を表示します:
  Project URL       : https://xxxx.supabase.co
  anon/publishable  : eyJhbGciOi... (Project Settings -> API)
事前に Supabase の SQL Editor で supabase/schema.sql を実行してください。
ビルド時に --dart-define で埋め込むこともできます (その場合この画面は出ません)。
