# レシート帳 — Receipt & Invoice Tracker (Flutter)

Cross-platform app (iOS / Android / Web / Windows / macOS / Linux) for tracking
Japanese paper receipts and invoices with a **dual scanner**:

- **1D barcode engine** — JAN-13 / EAN-8 / UPC-A / Code 128 / Code 39 / ITF via
  `mobile_scanner` (ML Kit on mobile, HTML5/WebRTC + ZXing on Web).
- **AI extraction engine** — the captured JPEG is sent to **Gemini Flash**
  through the **direct Google AI Studio / Gemini Developer API** with a JSON
  response schema. **ML Kit** (Android/iOS) and **Tesseract.js (WASM)**
  (Web) remain automatic fallbacks when AI is offline, unavailable or out of
  quota. No Cloud Functions, Firebase Storage, Blaze plan or credit card are
  required.

AI returns merchant, purchase date (including Reiwa dates converted to ISO),
total, subtotal, 8%/10% tax, invoice number (T + 13 digits), line items and a
suggested category that is auto-selected in the review form. The
local parser is kept as the fallback and handles **store name, date/time**
(`2026年10月19日`, `令和8年10月19日`, `R8.10.19`, `2026/10/19`), **total**
(`合計`, `税込合計`, `¥`), **subtotal** (`小計`) and **consumption tax**
(`消費税 8% / 10%`, `8%対象`, `内消費税`). Everything is reviewed and editable
before saving. **The receipt photo is never stored** — it lives in memory for
the review screen, is sent to Google only for AI processing, and is discarded
when the user saves or leaves.

---

## Live website

**https://receipt-tracker-2ec.pages.dev/**

The app opens directly on the **Firebase login / sign-up** screen. There is no
local-only mode and no connection-setup screen. One account syncs receipts,
line items, categories and budgets across phones and desktop browsers. Receipt
photos are never uploaded, saved or exported.

On the web, the scanner uses the browser's **HTML5/WebRTC camera**
(`getUserMedia`) for live barcode detection and frame capture. It asks the
active `MediaStreamTrack` for the highest practical resolution and continuous
autofocus, and tapping the preview re-focuses at that point when the browser
exposes focus constraints. iOS Safari (which does not support those constraints)
and other browsers also get a **「端末のカメラを使う」** button backed by
`<input type="file" accept="image/*" capture="environment">`. If camera access is
explicitly denied, the scanner falls back to photo upload and manual entry.

---

## Firebase project

The Web + mobile configuration is hard-coded in
`lib/core/config/firebase_config.dart`:

| Setting | Value |
| --- | --- |
| Project ID | `receipt-tracker-78d9f` |
| Auth domain | `receipt-tracker-78d9f.firebaseapp.com` |
| Storage bucket | `receipt-tracker-78d9f.firebasestorage.app` |
| App ID | `1:298768350843:web:2a2f828d62ba18d8992cde` |

Required one-time setup in the Firebase console:

1. **Authentication → Sign-in method → Email/Password** → enable.
2. **Firestore Database** → create the database.
3. Deploy the rules in [`firestore.rules`](firestore.rules):

   ```bash
   firebase deploy --only firestore:rules
   ```

4. **Authentication → Settings → Authorized domains** → add
   `receipt-tracker-2ec.pages.dev`. `localhost` is already authorized.
5. **Gemini API key** → AI scans go through the Cloudflare Worker
   (`receipt-tracker-backend`) by default, so the key lives in the Worker:
   `npx wrangler secret put GEMINI_API_KEY`. The key is never committed or
   bundled into the web app. Restrict it to the Generative Language API.
   A personal key saved in Settings bypasses the Worker; without either the
   scanner falls back to on-device OCR. The app defaults to the stable
   `gemini-3.1-flash-lite` model and tries the stable `gemini-3.5-flash-lite`,
   `gemini-3.6-flash` and `gemini-3.8-flash` fallbacks. Override with
   `--dart-define=GEMINI_RECEIPT_MODEL=...` if needed.
6. **App Check** → register the web app, create a reCAPTCHA v3 site key, then set
   the `RECAPTCHA_V3_SITE_KEY` build value (or the GitHub Actions repository
   secret of the same name). On web, debug builds use the App Check debug
   provider; native debug builds use the Android/Apple debug providers. App Check
   enforcement can be enabled in the console once tokens are flowing. If no site
   key is supplied, the app still starts and AI automatically falls back to local
   OCR.

### Bring your own Gemini key (optional)

Users may save their own Gemini API key from **Settings → AIキー（Gemini・任意）**.
It bypasses the shared backend and its daily limit.

1. Create a key in [Google AI Studio](https://aistudio.google.com/app/apikey).
2. In Google Cloud / AI Studio key restrictions:
   - **Application restrictions → HTTP referrers**: add
     `https://receipt-tracker-2ec.pages.dev/*`
   - **API restrictions**: allow only the **Generative Language API**
     (Gemini API)
3. Paste the key in Settings, then use **Save** and optionally **キーをテスト**.

The key is stored only in the browser's `localStorage` for the current origin
and is sent directly to Google's Gemini API. It is never written to Firestore,
committed to the repository, or logged. Without a saved key the app uses the
Cloudflare Worker (10 scans per user per day); if the Worker is unavailable the
scanner falls back to on-device OCR.

> Any key used in a frontend web app is visible to the user's browser. Restrict
> it by HTTP referrer and API, and rotate it if it is exposed.

### Firestore layout

```
users/{userId}/receipts/{receiptId}
  merchant, purchased_at, total_amount, subtotal_amount,
  tax_8_amount, tax_10_amount, barcode_id (invoice / reference no.),
  items[], raw_ocr_text, source, created_at, updated_at, ...

users/{userId}/coupons/{couponId}
  name, merchant, valid_from, valid_until,
  discount_amount_or_percent, status (active/used/expired),
  receipt_id, created_at, updated_at

users/{userId}/categories/{categoryId}
users/{userId}/budgets/{yyyy-MM}
```

**No image field is written.** Older documents that still contain
`image_base64` are tolerated when read, but the field is ignored and is not
displayed, exported or copied on update. Line items are embedded in the same
document, so a receipt + items are written atomically.

`firestore.rules` allows each authenticated user to read/write only their own
`users/{uid}/**` data.

---

## Feature summary

| Area | Implemented |
| --- | --- |
| Auth | Firebase Email/Password, password reset, persistent sessions |
| Sync | Firestore per-user receipts/items, categories and budgets (no photos) |
| Scan | Live 1D barcode (duplicate guard), tap-to-focus web camera, device-camera input, AI extraction, auto-detect and long-receipt modes |
| Parse | Gemini structured JSON (merchant, ISO/Reiwa date, total, subtotal, 8%/10% tax, invoice no., items), with parser fallback |
| Review | In-memory image preview, editable extracted items directly below it, header, tax, category, due date, notes, warnings and duplicate banner |
| Coupons | Printed coupons extracted with name / validFrom / validUntil / discount, saved per receipt, daily reminders with **Mark as Used** / **Remind Tomorrow**, automatic expiry |
| Categorize | 8 seeded categories + custom categories with colour & icon |
| Dashboard | Month/day grouping, list/grid views, monthly subtotals |
| Search/Filter | Merchant/note/barcode search, category chips, 今月/先月, custom ranges |
| Analytics | 6-month bars, category donut, top merchants, monthly metrics (`fl_chart`) |
| Languages | Japanese / English / Arabic (RTL) selector in Settings |
| Export | UTF-8 CSV for Excel / Numbers (no images) |

---

## Project structure

```
lib/
├── main.dart                       # intl + Firebase.initializeApp
├── app.dart                        # MaterialApp.router, theme, locale
├── core/
│   ├── config/                     # FirebaseOptions, App Check and Gemini model/key
│   ├── localization/               # AppLanguage, AppLocalizations, AppText
│   ├── router/                     # auth redirect + responsive shell
│   ├── theme/                      # Material 3 light/dark
│   └── utils/                      # money/date formatting, barcode checks
├── domain/
│   ├── models/                     # receipt, item, category, budget, filter
│   └── parser/                     # OCR post-processing heuristics
├── data/
│   ├── providers.dart              # Riverpod graph (Firebase auth, repos, queries)
│   ├── repositories/               # auth_repository, receipt_repository,
│   │                               # category_repository, budget_repository
│   └── services/
│       ├── image_input.dart        # native camera / photo fallback
│       ├── camera/                 # web <video> capture, focus constraints, file-capture input
│       └── ocr/                    # direct Gemini API + ML Kit / Tesseract.js fallback
└── features/
    ├── auth/ scan/ review/
    ├── dashboard/ receipts/ categories/ budget/
    └── settings/
```

### Data flow

```
 camera / image ─► Gemini Flash (Google AI Studio) ─┐
                         JSON response schema          │
                         │ error / offline / quota     │
                         ▼                             │
                   ML Kit / Tesseract.js ─► ReceiptParser
                         merchant/date/total/tax/items │
                                                        ▼
 1D barcode ──► JAN-13 / Code128 ───────────────► ReviewPage (edit)
                                                        ▼
                         Firebase Auth + Firestore users/{uid}/receipts
                         (photo kept in memory only; discarded on save/leave)
                                                        ▼
                         Dashboard / filters / analytics (all devices)
```

---

## Packages (and why)

| Package | Purpose |
| --- | --- |
| `flutter_riverpod` | State management & DI |
| `go_router` | Declarative navigation + auth redirect |
| `firebase_core` | Firebase app initialization |
| `firebase_auth` | Email/password auth and persistent sessions |
| `cloud_firestore` | Per-user receipts, items, categories and budgets |
| `google_generative_ai` | Direct Gemini Developer API client for Flutter Web (`gemini-3.1-flash-lite` primary, with stable fallbacks). This package is deprecated upstream; the planned replacement is Firebase AI Logic (`firebase_ai`). |
| `firebase_app_check` | App Check protection for Firebase requests |
| `mobile_scanner` | 1D barcode scanning: ML Kit mobile, WebRTC + ZXing web |
| `google_mlkit_text_recognition` | On-device OCR (Android/iOS, ja + en) |
| `image_picker` | Native camera capture / photo fallback |
| `web` | Web camera frame capture, MediaStreamTrack focus constraints + Tesseract.js interop |
| `web/tesseract.min.js` | Client-side fallback OCR for Web (worker/WASM/lang data from CDN, cached) |
| `web/zxing.min.js` | Bundled ZXing browser build (Apache-2.0) |
| `path_provider` | Temp file for ML Kit `InputImage` |
| `fl_chart` | Monthly bars + category donut |
| `intl` | Locale-aware date formatting (ja/en/ar) |
| `shared_preferences` | Theme + language preferences, coupon action journal / reminder state |
| `http` | Worker transport for AI scans without a personal key |
| `flutter_local_notifications` | Daily coupon reminders + action buttons (Android/iOS/macOS/web) |
| `timezone` | Absolute scheduling times for reminders |

---

## Build & run

```bash
flutter pub get
flutter run
```

Release builds:

```bash
flutter build apk --release --split-per-abi
flutter build web --release \
  --dart-define=RECAPTCHA_V3_SITE_KEY=6L...
flutter build windows --release   # Windows host + VS C++ + Developer Mode
flutter build ipa --release       # macOS host + Xcode + signing
```

Android requires `minSdk 24` (Firebase) and the `INTERNET` permission, both
already configured in the project.

### Cloudflare Pages

Pushing to `main` runs [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml),
which builds the web app and deploys `build/web` to the Cloudflare Pages project
`receipt-tracker` (`https://receipt-tracker-2ec.pages.dev`). The hard-coded
Firebase config is included in the build. Add an optional
`RECAPTCHA_V3_SITE_KEY` repository secret to enable App Check for Firebase
services. AI extraction uses the `receipt-tracker-backend` Worker; its
`GEMINI_API_KEY` is a Worker secret, not a repository secret.

Remember to add the Cloudflare Pages hostname to Firebase Auth
**Authorized domains**.

### Tests

```bash
flutter analyze --no-fatal-infos
flutter test
```

The parser tests cover Japanese dates (era/full/2-digit), total vs subtotal vs
change amounts, 8%/10% tax lines, tax-inclusive bases, reference numbers and
line-item extraction.

---

## Coupons & reminders

Gemini extracts a printed coupon (`name`, `valid_from`, `valid_until`,
`discount_amount_or_percent`) with the receipt. Saving a new receipt creates a
`users/{uid}/coupons` document (rescans of the same coupon are deduplicated).

* **Android / iOS / macOS** - `flutter_local_notifications` schedules one
  notification per active coupon per day at 09:00 local time until
  `valid_until` (capped at 90 days; coupons without an expiry are scheduled 30
  days ahead and re-planned on app launch). Android uses inexact alarms, so no
  exact-alarm permission is required.
* **Web** - browsers cannot schedule notifications, so today's reminder is
  shown once per day when the app is opened (Chrome/Edge show the action
  buttons; Firefox/Safari do not support actions).
* Actions - **Mark as Used** writes `status: used`; **Remind Tomorrow**
  suppresses the rest of today and resumes the next day. Actions pressed while
  the app is terminated are journalled in `SharedPreferences` by a background
  isolate and applied on the next launch.
* Expiry - `expireOverdue()` flips active coupons to `expired` after the
  `valid_until` day on app launch, resume, and whenever the coupon list loads.

Notification permission is requested from the **クーポン** page (web requires a
user gesture). Use `--dart-define=RECEIPT_BACKEND_URL=...` only for the AI
backend; reminders are fully local.

---

## How the scanning pipeline works

1. **Barcode mode** — `mobile_scanner` streams barcode captures (ML Kit on
   Android/iOS, ZXing over `getUserMedia` on web). The first non-empty value is
   stored and the review screen opens with the barcode / invoice number filled.
2. **AI OCR mode** — a still image is captured from the live web frame, the
   device-camera file input, or `image_picker` on mobile. The JPEG is sent to
   `AiReceiptOcrService` (direct Google AI Studio, Gemini `gemini-3.1-flash-lite`
   with model fallbacks) with a JSON response
   schema, then mapped into `ReceiptDraft` / `ReceiptItem`.
3. **Automatic fallback** — if Gemini errors, is offline or is out of quota, the
   existing ML Kit (mobile) / Tesseract.js (web) service and `ReceiptParser` run
   instead. The UI shows which engine is working and a clear Japanese/en/ar
   message when the fallback is used.
4. **Auto mode** — barcode first, then AI/OCR, merging both into the same draft.
5. **Long receipt** — multiple overlapping captures are merged by
   `ReceiptTextMerger` using the on-device/browser OCR path before parsing.
6. **Review** — the captured photo is shown from memory above the editable
   extracted item table; duplicate barcodes block saving.
7. **Save** — only receipt JSON + items are written to
   `users/{uid}/receipts/{receiptId}`. The in-memory image reference is dropped
   when the screen closes or the receipt is saved.

---

## Languages

Settings → Language offers **日本語 / English / العربية**. The choice is
persisted per device; Arabic switches the whole UI to RTL and date formatting
uses the selected locale.
