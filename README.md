# レシート帳 — Receipt & Invoice Tracker (Flutter)

Cross-platform app (iOS / Android / Web / Windows / macOS / Linux) for tracking
Japanese paper receipts and invoices with a **dual scanner**:

- **1D barcode engine** — JAN-13 / EAN-8 / UPC-A / Code 128 / Code 39 / ITF via
  `mobile_scanner` (ML Kit on mobile, HTML5/WebRTC + ZXing on Web).
- **AI extraction engine** — the captured JPEG is sent to **Gemini Flash**
  through **Firebase AI Logic** (Gemini Developer API, Spark/free tier) with a
  JSON response schema. **ML Kit** (Android/iOS) and **Tesseract.js (WASM)**
  (Web) remain automatic fallbacks when AI is offline, unavailable or out of
  quota. No Cloud Functions, Firebase Storage, Blaze plan or credit card are
  required.

AI returns merchant, purchase date (including Reiwa dates converted to ISO),
total, subtotal, 8%/10% tax, invoice number (T + 13 digits) and line items. The
local parser is kept as the fallback and handles **store name, date/time**
(`2026年10月19日`, `令和8年10月19日`, `R8.10.19`, `2026/10/19`), **total**
(`合計`, `税込合計`, `¥`), **subtotal** (`小計`) and **consumption tax**
(`消費税 8% / 10%`, `8%対象`, `内消費税`). Everything is reviewed and editable
before saving. **The receipt photo is never stored** — it lives in memory for
the review screen, is sent to Google only for AI processing, and is discarded
when the user saves or leaves.

---

## Live website

**https://malashraftulimat.github.io/receipt-tracker/**

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
   `malashraftulimat.github.io`. `localhost` is already authorized.
5. **Firebase AI Logic** → Get started (Gemini Developer API backend, Spark plan).
   The app uses the current Flash model documented by Firebase: `gemini-3.8-flash`.
6. **App Check** → register the web app, create a reCAPTCHA v3 site key, then set
   the `RECAPTCHA_V3_SITE_KEY` build value (or the GitHub Actions repository
   secret of the same name). On web, debug builds use the App Check debug
   provider; native debug builds use the Android/Apple debug providers. App Check
   enforcement can be enabled in the console once tokens are flowing. If no site
   key is supplied, the app still starts and AI automatically falls back to local
   OCR.

### Firestore layout

```
users/{userId}/receipts/{receiptId}
  merchant, purchased_at, total_amount, subtotal_amount,
  tax_8_amount, tax_10_amount, barcode_id (invoice / reference no.),
  items[], raw_ocr_text, source, created_at, updated_at, ...

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
│   ├── config/                     # hard-coded FirebaseOptions + App Check key
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
│       └── ocr/                    # Gemini AI Logic + ML Kit / Tesseract.js fallback
└── features/
    ├── auth/ scan/ review/
    ├── dashboard/ receipts/ categories/ budget/
    └── settings/
```

### Data flow

```
 camera / image ─► Gemini Flash (Firebase AI Logic) ─┐
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
| `firebase_ai` | Gemini Developer API via Firebase AI Logic (`gemini-3.8-flash`) |
| `firebase_app_check` | App Check protection for AI / Firebase requests |
| `mobile_scanner` | 1D barcode scanning: ML Kit mobile, WebRTC + ZXing web |
| `google_mlkit_text_recognition` | On-device OCR (Android/iOS, ja + en) |
| `image_picker` | Native camera capture / photo fallback |
| `web` | Web camera frame capture, MediaStreamTrack focus constraints + Tesseract.js interop |
| `web/tesseract.min.js` | Client-side fallback OCR for Web (worker/WASM/lang data from CDN, cached) |
| `web/zxing.min.js` | Bundled ZXing browser build (Apache-2.0) |
| `path_provider` | Temp file for ML Kit `InputImage` |
| `fl_chart` | Monthly bars + category donut |
| `intl` | Locale-aware date formatting (ja/en/ar) |
| `shared_preferences` | Theme + language preferences |

---

## Build & run

```bash
flutter pub get
flutter run
```

Release builds:

```bash
flutter build apk --release --split-per-abi
flutter build web --release --base-href=/receipt-tracker/ \
  --dart-define=RECAPTCHA_V3_SITE_KEY=6L...   # optional App Check key
flutter build windows --release   # Windows host + VS C++ + Developer Mode
flutter build ipa --release       # macOS host + Xcode + signing
```

Android requires `minSdk 24` (Firebase) and the `INTERNET` permission, both
already configured in the project.

### GitHub Pages

Pushing to `main` runs [`.github/workflows/pages.yml`](.github/workflows/pages.yml),
which runs `flutter analyze`, `flutter test`, builds the web app with the
repository base path and deploys `build/web`. The hard-coded Firebase config is
included in the build. Add an optional `RECAPTCHA_V3_SITE_KEY` repository
secret to enable App Check for the deployed site; without it the build succeeds
and AI falls back to local OCR.

Remember to add the Pages hostname to Firebase Auth **Authorized domains**.

### Tests

```bash
flutter analyze --no-fatal-infos
flutter test
```

The parser tests cover Japanese dates (era/full/2-digit), total vs subtotal vs
change amounts, 8%/10% tax lines, tax-inclusive bases, reference numbers and
line-item extraction.

---

## How the scanning pipeline works

1. **Barcode mode** — `mobile_scanner` streams barcode captures (ML Kit on
   Android/iOS, ZXing over `getUserMedia` on web). The first non-empty value is
   stored and the review screen opens with the barcode / invoice number filled.
2. **AI OCR mode** — a still image is captured from the live web frame, the
   device-camera file input, or `image_picker` on mobile. The JPEG is sent to
   `AiReceiptOcrService` (Gemini `gemini-3.8-flash`) with a JSON response
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
