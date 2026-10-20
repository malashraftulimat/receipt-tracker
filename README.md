# レシート帳 — Receipt & Invoice Tracker (Flutter)

Cross-platform app (iOS / Android / Web / Windows / macOS / Linux) for tracking
Japanese paper receipts and invoices with a **dual scanner**:

- **1D barcode engine** — JAN-13 / EAN-8 / UPC-A / Code 128 / Code 39 / ITF via
  `mobile_scanner` (ML Kit on mobile, HTML5/WebRTC + ZXing on Web).
- **OCR engine** — Japanese + English text recognition via **ML Kit** on
  Android/iOS and **Tesseract.js (WASM)** directly in the browser on Web.
  No Cloud Functions, Firebase Storage, Blaze plan or credit card are required.

Both engines feed a deterministic parser that detects **store name, date/time**
(`2026年10月19日`, `令和8年10月19日`, `R8.10.19`, `2026/10/19`), **total**
(`合計`, `税込合計`, `¥`), **subtotal** (`小計`) and **consumption tax**
(`消費税 8% / 10%`, `8%対象`, `内消費税`). Everything is reviewed and editable
before saving.

---

## Live website

**https://malashraftulimat.github.io/receipt-tracker/**

The app opens directly on the **Firebase login / sign-up** screen. There is no
local-only mode and no connection-setup screen. One account syncs receipts,
line items, categories, budgets and receipt images across phones and desktop
browsers.

On the web, the scanner uses the browser's **HTML5/WebRTC camera**
(`getUserMedia`) for live barcode detection and OCR frame capture. If camera
access is explicitly denied, the scanner falls back to photo upload and manual
entry.

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

### Firestore layout

```
users/{userId}/receipts/{receiptId}
  merchant, purchased_at, total_amount, tax_8_amount, tax_10_amount,
  barcode_id (invoice / reference no.), items[], raw_ocr_text,
  image_base64, created_at, updated_at, ...

users/{userId}/categories/{categoryId}
users/{userId}/budgets/{yyyy-MM}
```

Receipt images are resized/compressed by the `image` package and stored as
base64 in the receipt document (Firestore's 1 MiB document limit). Line items
are embedded in the same document, so a receipt + items are written atomically.

`firestore.rules` allows each authenticated user to read/write only their own
`users/{uid}/**` data.

---

## Feature summary

| Area | Implemented |
| --- | --- |
| Auth | Firebase Email/Password, password reset, persistent sessions |
| Sync | Firestore per-user receipts/items, categories, budgets and images |
| Scan | Live 1D barcode (duplicate guard), OCR capture, auto-detect and long-receipt modes |
| Parse | JP dates, merchant scoring, totals/subtotals, 8%/10% tax, invoice numbers and line items |
| Review | Editable header, items, tax, category, due date, notes, OCR warnings and duplicate banner |
| Categorize | 8 seeded categories + custom categories with colour & icon |
| Dashboard | Month/day grouping, list/grid views, monthly subtotals |
| Search/Filter | Merchant/note/barcode search, category chips, 今月/先月, custom ranges |
| Analytics | 6-month bars, category donut, top merchants, monthly metrics (`fl_chart`) |
| Languages | Japanese / English / Arabic (RTL) selector in Settings |
| Export | UTF-8 CSV for Excel / Numbers |

---

## Project structure

```
lib/
├── main.dart                       # intl + Firebase.initializeApp
├── app.dart                        # MaterialApp.router, theme, locale
├── core/
│   ├── config/firebase_config.dart # hard-coded FirebaseOptions
│   ├── localization/               # AppLanguage, AppLocalizations, AppText
│   ├── router/                     # auth redirect + responsive shell
│   ├── theme/                      # Material 3 light/dark
│   └── utils/                      # money/date formatting, image compression, barcode checks
├── domain/
│   ├── models/                     # receipt, item, category, budget, filter
│   └── parser/                     # OCR post-processing heuristics
├── data/
│   ├── providers.dart              # Riverpod graph (Firebase auth, repos, queries)
│   ├── repositories/               # auth_repository, receipt_repository,
│   │                               # category_repository, budget_repository
│   └── services/
│       ├── image_input.dart        # native camera / photo fallback
│       ├── camera/                 # web <video> frame capture for OCR
│       └── ocr/                    # ML Kit (mobile) + Tesseract.js (web)
└── features/
    ├── auth/ scan/ review/
    ├── dashboard/ receipts/ categories/ budget/
    └── settings/
```

### Data flow

```
 camera / image ─► OCR service ─► ReceiptParser ─┐
                   ML Kit /      merchant/date/  │
                   Tesseract.js  total/tax/items │
                                                 ▼
 1D barcode ──► JAN-13 / Code128 ──────────► ReviewPage (edit)
                                                 ▼
                          Firebase Auth + Firestore users/{uid}/receipts
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
| `mobile_scanner` | 1D barcode scanning: ML Kit mobile, WebRTC + ZXing web |
| `google_mlkit_text_recognition` | On-device OCR (Android/iOS, ja + en) |
| `image_picker` | Native camera capture / photo fallback |
| `image` | Resize + JPEG compression before storing base64 in Firestore |
| `web` | Web camera frame capture + Tesseract.js interop |
| `web/tesseract.min.js` | Client-side OCR engine for Web (worker/WASM/lang data from CDN, cached) |
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
flutter build web --release
flutter build windows --release   # Windows host + VS C++ + Developer Mode
flutter build ipa --release       # macOS host + Xcode + signing
```

Android requires `minSdk 24` (Firebase) and the `INTERNET` permission, both
already configured in the project.

### GitHub Pages

Pushing to `main` runs [`.github/workflows/pages.yml`](.github/workflows/pages.yml),
which runs `flutter analyze`, `flutter test`, builds the web app with the
repository base path and deploys `build/web`. The hard-coded Firebase config is
included in the build; no repository secrets or `--dart-define` values are
needed.

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
2. **OCR mode** — a still image is captured from the live web frame or via
   `image_picker` on mobile. It is recognised by ML Kit (mobile) or Tesseract.js
   (web), then `ReceiptParser` extracts store, date, totals, tax and items.
3. **Auto mode** — barcode first, then OCR, merging both into the same draft.
4. **Long receipt** — multiple overlapping captures are merged by
   `ReceiptTextMerger` before parsing.
5. **Review** — all fields are editable; duplicate barcodes block saving.
6. **Save** — the compressed image + receipt JSON + items are written to
   `users/{uid}/receipts/{receiptId}` in Firestore.

---

## Languages

Settings → Language offers **日本語 / English / العربية**. The choice is
persisted per device; Arabic switches the whole UI to RTL and date formatting
uses the selected locale.
