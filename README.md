# レシート帳 — Receipt & Invoice Tracker (Flutter)

Cross-platform app (iOS / Android / Web / Windows / macOS / Linux) for tracking Japanese
paper receipts and invoices with a **dual scanner**:

- **1D barcode engine** — JAN-13 / EAN-8 / UPC-A / Code 128 / Code 39 / ITF via `mobile_scanner`,
  used to capture invoice / payment reference numbers and to block duplicate entries.
- **OCR engine** — Japanese + English text recognition via **ML Kit** on mobile and a
  **Supabase Edge Function (Google Cloud Vision)** on web/desktop.

Both engines feed a deterministic parser that detects **store name, date/time
(`2026年10月19日`, `令和8年10月19日`, `R8.10.19`, `2026/10/19`), total (`合計`, `税込合計`,
`¥`), subtotal (`小計`) and consumption tax (`消費税 8% / 10%`, `8%対象`, `内消費税`)**.
Everything is reviewed and editable before saving.

---

## Live website

**https://malashraftulimat.github.io/receipt-tracker/**

Opens in any phone or desktop browser. On first launch choose:

* **この端末だけで使う（ローカルアカウント）** — email + password sign-up stored
  on-device (salted SHA-256), no server. Receipts, categories and photos live in
  the browser (`localStorage`) and are scoped per account.
* **Supabase に接続** — paste your Project URL + anon key for multi-device sync.

Live barcode scanning works in Chrome/Edge/Safari over HTTPS; OCR on the web
uses the `ocr` edge function (local mode only offers manual entry there).

---

## 0. Built applications (where the platform copies are)

| What | Where |
| --- | --- |
| Android APKs (built, installable) | `dist/android/*.apk` |
| Web / PWA build (built) | `dist/receipt_tracker-1.0.0-web.zip` and `build/web/` |
| Android project (Gradle) | `android/` |
| iOS project (Xcode) | `ios/Runner.xcworkspace` |
| Windows project (C++ runner) | `windows/runner/` |
| Web project | `web/` |
| macOS / Linux projects | `macos/`, `linux/` |
| CI that builds all four | `.github/workflows/build.yml` |

Android and Web are compiled on this machine. **iOS requires macOS + Xcode**
and **Windows requires Visual Studio 2022 + Developer Mode**, so those two are
built by the GitHub Actions workflow (or locally following
[`docs/BUILDING.md`](docs/BUILDING.md)). Install notes are in
[`dist/README.txt`](dist/README.txt).

First launch of any build shows a **接続設定** screen where you paste your
Supabase Project URL + anon/publishable key; it is stored locally and used from
then on. Credentials can also be baked in at build time with `--dart-define`.

---

## 1. Feature summary

| Area | Implemented |
| --- | --- |
| Auth | Email + password (Supabase Auth), password reset, session refresh |
| Sync | Postgres rows + Storage images + categories, per-user RLS, realtime-ready |
| Scan | Live 1D barcode scanning (auto duplicate guard), OCR capture, "auto" mode that merges barcode + OCR |
| Parse | JP date (era/full/2-digit), merchant scoring, total/subtotal keywords, 8%/10% tax incl. tax-inclusive bases, invoice `T+13` numbers |
| Review | Editable merchant / date / time / total / subtotal / tax 8% / tax 10% / barcode / category / note, OCR warnings, tax cross-check, duplicate banner |
| Categorize | 8 seeded categories + custom categories with colour & icon |
| Dashboard | Year → month → day grouping, list **and** grid views, monthly subtotals |
| Search/Filter | Full-text-ish search (merchant / note / barcode), category chips, 今月/先月, custom date range |
| Analytics | 6-month bar chart, current-month category donut, top merchants, monthly metrics (`fl_chart`) |
| Responsive | `NavigationBar` on phones, `NavigationRail` + analytics side panel on desktop |
| State | Riverpod (`Notifier` / `FutureProvider` / `StreamProvider`), go_router, repository layer |

---

## 2. Project structure

```
receipt_tracker/
├── pubspec.yaml
├── analysis_options.yaml
├── android/                        # Gradle project  (APK built here)
├── ios/                            # Xcode project  (requires macOS to build)
├── windows/                        # Win32 C++ runner (requires VS 2022)
├── macos/  linux/                  # desktop runners
├── web/                            # PWA shell      (built here)
├── dist/                           # compiled APKs + web zip + install notes
├── .github/workflows/build.yml     # CI: Android / Windows / iOS / Web artifacts
├── supabase/
│   ├── schema.sql                  # tables, RLS, storage policies, seed trigger
│   └── functions/ocr/index.ts      # web/desktop OCR fallback (Cloud Vision)
├── docs/
│   ├── PLATFORM_SETUP.md           # Android / iOS / Web / Desktop config
│   └── BUILDING.md                 # per-platform build & signing
├── lib/
│   ├── main.dart                   # bootstrap: intl(ja) + Supabase.initialize
│   ├── app.dart                    # MaterialApp.router, theme, locale, config guard
│   ├── core/
│   │   ├── config/app_config.dart  # --dart-define values, bucket/function names
│   │   ├── router/app_router.dart  # auth redirect + shell routes
│   │   ├── router/app_shell.dart   # responsive NavigationRail / NavigationBar
│   │   ├── theme/app_theme.dart    # Material 3 light/dark
│   │   ├── theme/theme_mode_provider.dart
│   │   └── utils/                  # money & date formatting, responsive, barcode checks
│   ├── domain/
│   │   ├── models/receipt.dart
│   │   ├── models/receipt_draft.dart
│   │   ├── models/receipt_filter.dart
│   │   ├── models/category.dart
│   │   └── parser/receipt_parser.dart   # ★ OCR post-processing heuristics
│   ├── data/
│   │   ├── providers.dart          # Riverpod graph (client, repos, auth, queries)
│   │   ├── repositories/           # auth / receipt / category / storage
│   │   └── services/
│   │       ├── image_input.dart    # camera (mobile) / gallery (web, desktop)
│   │       └── ocr/                # interface + conditional platform impls
│   │           ├── ocr_service.dart        # OcrService + OcrResult + factory
│   │           ├── ocr_service_io.dart     # Android/iOS -> ML Kit, desktop -> remote
│   │           ├── ocr_service_web.dart    # Web -> Supabase Edge Function
│   │           ├── mlkit_ocr_service.dart
│   │           └── remote_ocr_service.dart
│   └── features/
│       ├── auth/auth_page.dart
│       ├── scan/scan_page.dart          # dual scanner UI
│       ├── scan/scan_session.dart       # mode + barcode session state
│       ├── review/review_page.dart      # confirm & edit before saving
│       ├── dashboard/dashboard_page.dart
│       ├── dashboard/analytics_provider.dart
│       ├── dashboard/widgets/           # filter bar, list/grid, charts, tiles
│       ├── receipts/receipt_detail_page.dart
│       ├── categories/categories_page.dart
│       └── settings/settings_page.dart
└── test/
    ├── receipt_parser_test.dart    # JP date/tax/total/merchant cases
    └── formatters_test.dart
```

### Data flow

```
                 ┌──────────────┐        ┌────────────────────────┐
 camera / image ─►│ OCR service  │───────►│ ReceiptParser          │
                 │ ML Kit /     │  text  │ merchant / date / ¥ /  │
                 │ Cloud Vision │        │ subtotal / tax 8,10    │
                 └──────────────┘        └───────────┬────────────┘
                                                     │ ParsedReceipt
 1D barcode ──► JAN-13 / Code128 value ─────────────►│
                                                     ▼
                                          ┌─────────────────────┐
                                          │ ReviewPage (edit)   │
                                          └─────────┬───────────┘
                                                    ▼
                              Supabase Postgres (receipts) + Storage (images)
                                                    ▼
                              Dashboard / filters / analytics (all devices)
```

---

## 3. Packages (and why)

| Package | Purpose |
| --- | --- |
| `flutter_riverpod` | State management & DI (repositories, filters, queries, auth stream) |
| `go_router` | Declarative navigation, auth redirect, deep links to `/receipt/:id` |
| `supabase_flutter` | Email/password auth, Postgres client, Storage, Edge Functions |
| `mobile_scanner` | 1D/2D barcode scanning (`ean13`, `ean8`, `code128`, `code39`, `itf`, `upcA`) |
| `google_mlkit_text_recognition` | On-device OCR (Android/iOS) with the Japanese script model |
| `image_picker` | Camera capture on mobile, gallery/file picker on web & desktop |
| `path_provider` | Temp file needed by ML Kit `InputImage` |
| `fl_chart` | Monthly bar chart + category donut |
| `intl` | Japanese date formatting (`yyyy年M月d日(E)`) |
| `shared_preferences` | Persisted light/dark/system preference |
| `flutter_localizations` | Japanese Material/Dialog/Date picker strings |

---

## 4. Setup

### 4.1 Platform folders are already generated

`android/`, `ios/`, `windows/`, `web/`, `macos/` and `linux/` are checked in,
with the camera/ML Kit settings already applied. If you ever need to regenerate
them: `flutter create --platforms=android,ios,web,windows,macos,linux .`
(existing Dart code is kept). See [`docs/BUILDING.md`](docs/BUILDING.md) for
per-platform prerequisites and signing.

### 4.2 Supabase

1. Create a project at <https://supabase.com>.
2. Open **SQL Editor** and run [`supabase/schema.sql`](supabase/schema.sql).
   This creates `receipts`, `categories`, RLS policies, the private `receipts`
   storage bucket and a trigger that seeds default categories for new users.
3. (Optional, required for Web/desktop OCR) deploy the edge function:

   ```bash
   supabase functions deploy ocr
   supabase secrets set GOOGLE_VISION_API_KEY=xxxxx
   ```

4. Auth providers → **Email** is enabled by default. For quick local testing you may
   disable *Confirm email* (Authentication → Providers → Email).

### 4.3 Run

```bash
flutter pub get
flutter run                     # pick a device, then choose local mode or paste keys

# or bake the credentials in (no setup screen):
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=eyJ...
```

Builds:

```bash
flutter build apk --release --split-per-abi
flutter build web --release
flutter build windows --release   # Windows host + VS C++ + Developer Mode
flutter build ipa --release       # macOS host + Xcode + signing
```

### 4.4 Tests

```bash
flutter test
```

The parser tests cover Japanese dates (era / full / 2-digit), total vs subtotal vs
change amounts, 8%/10% tax lines, tax-inclusive bases and reference numbers.

---

## 5. How the scanning pipeline works

1. **Barcode mode** – `mobile_scanner` streams `BarcodeCapture`s. The first non-empty
   `rawValue` is stored in `scanSessionProvider` (JAN-13 check digit validated for
   display) and the review screen is opened immediately with `barcodeId` filled.
   A Postgres partial unique index `(user_id, barcode_id)` also prevents duplicates at
   the database level; the UI shows the existing receipt instead of saving a copy.
2. **OCR mode** – a still photo is taken (`image_picker`), recognised
   (`MlKitOcrService` on mobile, `RemoteOcrService` → edge function elsewhere), then
   `ReceiptParser` extracts structured fields.
3. **Auto mode** – barcode is detected first; a banner then offers
   “撮影して自動入力” which runs OCR and merges the barcode into the same draft.
4. **Review** – every field is editable; warnings from the parser (e.g. missing total,
   subtotal > total, tax > total) are shown, duplicate barcodes block the save button.
5. **Save** – image is uploaded to `receipts/<user-id>/<timestamp>.jpg`, the row is
   inserted/updated, and all relevant providers are invalidated.

### Parser heuristics (short version)

- Text is normalised (full-width → half-width, `￥` → `¥`, ideographic space → space).
- Dates / times / phone numbers / percentages / invoice numbers are **masked** before
  money extraction, so `2026年10月19日 14:32` never becomes an amount.
- Totals are looked up by keyword priority
  (`税込合計` → `合計金額` → `お会計` → … → `合計` → `計`), ignoring
  `税抜`, `お預り`, `お釣`, `カード`, `ポイント` lines; a max-value fallback is used
  when no keyword exists.
- Tax: lines containing `消費税`/`内税`/`税額` and `8%`/`10%` are parsed, `対象`/`課税`
  lines are treated as tax-inclusive bases, and missing amounts are derived
  (`base × rate / (100 + rate)`), with sanity checks that drop impossible values.
- Merchant: first ~12 lines are scored (index, store keywords like `店`/`マート`/
  `株式会社`, Japanese characters, length); boilerplate (`領収書`, `TEL`,
  `登録番号`, …) and date lines are rejected.

---

## 6. Known limitations / next steps

- **Web & desktop live camera**: `mobile_scanner`'s live preview is only wired to
  Android/iOS here. On desktop/web the app falls back to picking an image and running
  server OCR. (You can add a web barcode overlay using `mobile_scanner`'s web support
  if the browser exposes a camera.)
- **Server OCR cost**: Cloud Vision is billed per request; ML Kit on mobile is free and
  offline.
- Receipt images are stored privately and served with 7-day signed URLs; add a
  cleanup job if you need retention limits.
- Realtime subscriptions are not enabled by default (the dashboard refetches on
  pull-to-refresh / provider invalidation). Add
  `client.from('receipts').stream(primaryKey: ['id'])` for live multi-device updates.
