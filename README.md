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
total, subtotal, 8%/10% tax, the receipt's own number (伝票番号 / レシート番号 /
receipt barcode), the shop's qualified-invoice registration number
(登録番号, T + 13 digits) as a separate field, line items and a suggested
category that is auto-selected in the review form. The
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
  tax_8_amount, tax_10_amount,
  receipt_number (the receipt's own number; duplicate key),
  invoice_registration_number (登録番号, T + 13 digits; never a duplicate key),
  barcode_id (legacy mirror of receipt_number, read for old documents),
  payment_method (cash / credit_card / debit_card / bank_transfer /
                  direct_debit / qr_emoney / ic_card /
                  convenience_store / other, optional),
  wallet_id (optional; null for old documents),
  recurring_id (set when posted by a recurring transaction),
  items[], raw_ocr_text, source (barcode / ocr / manual),
  created_at, updated_at, ...

users/{userId}/coupons/{couponId}
  name, merchant, valid_from, valid_until,
  discount_amount_or_percent, status (active/used/expired),
  receipt_id, created_at, updated_at

users/{userId}/categories/{categoryId}
users/{userId}/budgets/{yyyy-MM}
  salary (monthly equivalent), savings_goal, fixed_expenses,
  overall_limit, category_limits (map categoryId -> amount),
  pay_cycle (daily/weekly/monthly), income_per_cycle, note,
  month, updated_at

users/{userId}/income_sources/{sourceId}
  name, cycle (daily/weekly/monthly),
  weekly_start_weekday, monthly_pay_day,
  amount_per_cycle, currency, wallet_id (optional),
  active, defines_budget_period (exactly one), created_at, updated_at

users/{userId}/income_entries/{entryId}
  amount, currency, received_at, source (free text),
  note, wallet_id (optional),
  recurring_id (set when posted by a recurring transaction),
  created_at, updated_at

users/{userId}/income_meta/state
  income_sources_migrated (one-time legacy migration marker)

users/{userId}/wallets/{walletId}
  name (free text), type (cash / bank / credit / debit / e_money /
                        transit / savings / points / other),
  currency, opening_balance, color_value, archived, last4 (optional),
  include_in_total, reserved,
  credit_limit, opening_available, closing_day, payment_due_day,
  settlement_wallet_id (credit cards only), created_at, updated_at

users/{userId}/wallet_transfers/{transferId}
  from_wallet_id, to_wallet_id, from_amount, to_amount,
  occurred_at, note, created_at, updated_at

users/{userId}/wallet_adjustments/{adjustmentId}
  wallet_id, amount, occurred_at, note, created_at, updated_at

users/{userId}/debts/{debtId}
  direction (i_lent / i_borrowed), counterparty (free text),
  amount, currency, date, due_date (optional), note,
  wallet_id (optional), repayments[] (id, amount, date, wallet_id, note),
  status (open / partial / settled), created_at, updated_at

users/{userId}/recurring_transactions/{recurringId}
  name, direction (expense / income), amount, currency,
  category_id, wallet_id, cycle (daily/weekly/monthly),
  weekly_start_weekday, monthly_pay_day, start_date,
  last_posted_at, active, note, created_at, updated_at
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
| Sync | Firestore per-user receipts/items, categories, budgets, income sources and one-off income (no photos) |
| Scan | Live 1D barcode (receipt-number duplicate guard), tap-to-focus web camera, device-camera input, AI extraction, auto-detect and long-receipt modes |
| Parse | Gemini structured JSON (merchant, ISO/Reiwa date, total, subtotal, 8%/10% tax, receipt no. and registration no. separately, items), with parser fallback |
| Review | In-memory image preview, editable extracted items directly below it, header, tax, category, payment method, due date, notes, warnings and duplicate banner |
| Quick payment | Receiptless expense (rent, transfers, money lent) saved into the same collection as `source = manual`: amount, date, category, required payment method, note |
| Coupons | Printed coupons extracted with name / validFrom / validUntil / discount, saved per receipt, daily reminders with **Mark as Used** / **Remind Tomorrow**, automatic expiry |
| Income | Multiple recurring income sources (daily/weekly/monthly payday anchors), one source drives budget pacing, one-off **Add income** with free-text source autocomplete, monthly-equivalent totals |
| Wallets | Cash, bank, debit, e-money, transit, savings, points and credit-card wallets; balances derived from transactions; optional last4 only |
| Transfers | Wallet-to-wallet transfers, including cross-currency transfers with both amounts entered explicitly, and credit-card repayments |
| Credit cards | Limit + available at setup, computed owed/available, closing and due days, settlement wallet, next payment due |
| Dashboard money | Available money / after obligations / net worth, with an expandable per-wallet list and card-due warning |
| FX | Display-currency conversion via Frankfurter v2 with open.er-api.com fallback, ~6h local cache, offline reuse and per-pair manual overrides |
| Debts | Money lent/borrowed, free-text person, partial repayments, optional wallet movements, open/partial/settled status, owed-to-me and I-owe totals |
| Reminders | In-app credit-card and debt due reminders, plus `.ics` **Add to calendar** export |
| Categorize | 8 seeded categories + custom categories with colour & icon |
| Dashboard | Month/day grouping, list/grid views, monthly subtotals |
| Search/Filter | Merchant/note/barcode search, category chips, payment-method filter, 今月/先月, custom ranges |
| Budget | Income-source pay cycle, overall limit, per-category monthly limits with 80%/100% warnings, savings goal, fixed costs, remaining-per-pay-period pacing, per-wallet spending |
| Recurring | Rent/subscriptions/fixed income posted automatically each cycle and included in the after-obligations number |
| Analytics | 6-month bars, category donut, payment-method breakdown, top merchants, monthly metrics (`fl_chart`) |
| Languages | Browser / system language auto-detection, header switcher (visible on login & register too), Japanese / English / Arabic (RTL) |
| Export | UTF-8 CSV for Excel / Numbers (no images); full CSV with wallets, transactions, income, debts and recurring |

---

## Income, budget & salary cycle

### Multiple income sources

Settings → **収入源 / Income sources** keeps a list of every way the user
receives money. Each source has a free-text name, a cycle (daily / weekly /
monthly), the matching payday anchor (weekday for weekly, day 1–28 or month end
for monthly), the amount **per cycle**, an active switch and an optional
destination wallet (Phase 2). Sources are stored in Firestore, so amounts and
anchors sync across devices.

Exactly one source is flagged **defines the budget period** (default: the first
source). Its payday anchor drives the current period and all existing pacing
logic on the dashboard and budget page. The other active sources still count as
income arriving on **their own paydays inside that period**. The app also shows
the monthly-equivalent total across all active sources.

When the feature is first opened for an existing account, the old single pay
cycle is migrated into one source named **Main** (`income_sources/main`): the
cycle and anchors come from the saved preference and the per-cycle amount comes
from the latest budget plan. A marker in `income_meta/state` prevents an
intentionally emptied list from being seeded again. Older budgets keep working;
the budget page now derives income from the sources and keeps savings goal and
fixed costs monthly.

### One-off income

The dashboard app-bar **収入を追加 / Add income** button (route `/income/new`)
records income that is not part of a recurring source: amount, date, a free-text
source (e.g. "sold an item", "Open Campus shift") and an optional note. Source
texts autocomplete from previous entries (tap a suggestion or start typing). The
entry is stored in `income_entries` and counted in the current period income;
a destination wallet is added in Phase 2.

Period income = recurring paydays inside the period + one-off entries inside
the period. Amounts in another currency are excluded (and counted in a note)
until conversion arrives in Phase 2.

The dashboard card and the budget page show the amount left for the current pay
period, its date range, the per-day allowance for the days remaining until the
next payday, and both the period income and the monthly-equivalent total.

### Quick payments (no receipt)

The **支払いを追加 / Add payment** screen (dashboard app-bar button, scan screen
button, route `/payment/new`) records expenses that have no receipt — rent,
bank transfers, money lent to a friend, and so on. It asks for amount (required),
date (defaults to today), category, payment method (required), an **optional
wallet** and a note. Only wallets with the same currency are offered.

There is no parallel payments store: the entry is written to
`users/{uid}/receipts` with `source = manual`, so the dashboard list, monthly
subtotals, budget pacing (including daily / weekly / monthly pay periods) and
analytics count it automatically. The note doubles as the list title when no
merchant is set.

Payment methods are a stored enum (`payment_method`, snake_case wire names,
localized ja/en/ar): cash, credit card, debit card, bank transfer, direct
debit / utility bills, QR / e-money, IC card (Suica / PASMO), convenience-store
payment and other. Scanned receipts can set the same field in the review screen
(optional, default **未設定**); documents written before the field existed simply
read back as unset. The dashboard shows a chip per list row, can filter by
method, and analytics includes a current-month breakdown per method.

### Wallets, credit cards, transfers and currencies

Settings → **ウォレット / Wallets** (route `/wallets`) manages any number of
wallets. Names, banks, card issuers and e-money services are **free text typed by
the user**; the app ships no bank or payment-service database. A wallet stores:

- type: cash, bank, credit, debit, e-money, transit IC, savings, points, other;
- any ISO-4217 currency, opening balance, colour, archived flag and `reserved`;
- an optional **last 4 digits only**. Full card numbers, CVV and PINs are never
  requested or stored. Card form fields are limited to four digits.
- `include_in_total`: default **false** for savings and points, **true** for the
  other types; archived wallets are always excluded. The user can override it.

**Balances are never stored.** Each wallet balance is computed as
`opening balance + income − spending + transfers in − transfers out ± adjustments`.
Receipts, quick payments and one-off income can select a matching-currency
wallet. A manual correction uses the **Adjust balance** action and is written as
an adjustment transaction (audit trail), not by editing a stored balance. Money
remains in each wallet's own currency; conversion is display-only.

**Transfers** (`wallet_transfers`) move money between wallets: withdrawing cash,
topping up e-money, or paying a credit-card bill. If the two wallets use
different currencies, both amounts are entered explicitly; no exchange rate is
stored.

**Credit cards** have no balance and are excluded from available money. At setup
the user enters the credit limit and the currently available amount, so the
starting owed amount is `limit − available`. Charges increase owed and reduce
available credit; a transfer to the card is a repayment that restores available
credit. Closing day, payment due day and an optional settlement bank wallet are
stored. The wallet detail shows limit, available, total owed, owed this cycle,
next due date and amount due.

**Dashboard money card.** The top dashboard card has a remembered segmented
control with three views:

1. **Available money** — sum of non-archived wallets with `include_in_total`,
   excluding credit cards, converted to the display currency.
2. **After obligations** — available money minus card dues minus recurring
   bills due before the next payday (recurring transactions arrive in Phase 4).
3. **Net worth** — all non-archived wallets including savings, plus debts owed
   to me, minus debts I owe, minus card dues.

Under the headline it always shows **After card obligations: X**. The line turns
into a warning colour when card dues are large relative to available money and
the next due date is within a few days. The expandable wallet list shows each
wallet's own-currency balance, the latest transaction and the converted value;
tapping opens the wallet detail.

**Display currency and rates.** Settings → **通貨 / Currency** chooses both the
currency for new receipts/plans and the **base currency for converted totals**.
Rates come from [Frankfurter v2](https://api.frankfurter.dev) (`/v2/rates`) with
[open.er-api.com](https://open.er-api.com) as a CORS-enabled fallback. The table
is cached locally for about six hours, reused offline, and the app shows
**“Rates as of …”**. A **manual rate override per currency pair** always wins
over fetched/cached rates and is marked as manual. If a currency has no rate,
its wallet is shown in its own currency, excluded from the converted total, and
a visible note explains why — the app never guesses.

### Debts and reminders

Settings → **貸し借り / Debts** (route `/debts`) records money lent or borrowed
with a free-text person name, amount, currency, date, optional due date and
note. An optional wallet link records the money movement in that wallet's
balance. Repayments are added one by one; each repayment can also link a wallet.
Status is derived as **open → partial → settled** from the repaid amount, and a
**Mark as settled** action can close the remaining balance without a payment.
Debts never count in “available money”; outstanding balances are included in net
worth (owed to me adds, I owe subtracts). The screen shows the two converted
totals, filters by status and person, and keeps the repayment history.

The dashboard shows an **in-app reminders card** for credit-card payment dates
and debt due dates a few days before, on the day, and while overdue. Each item
has **Add to calendar**, which exports an `.ics` file. The card's info dialog and
this README are explicit about limits:

- **Browser tab** — reminders appear only while the app is open; there are no
  background notifications.
- **Installed PWA** — closing the browser stops them. Web Push needs a separate
  push service and permission; it is not promised by this build.
- **iOS** — web push works only on iOS 16.4+ and only after adding the site to
  the Home Screen.
- **Android** — Chrome web push is available with permission and a push service.
- **Native app** — local notifications can be scheduled; scheduling card/debt
  reminders is left as a future enhancement. This build provides in-app
  reminders and `.ics` calendar export.

### Budget limits, recurring transactions and full export

The budget page supports an **overall monthly limit** and **per-category
monthly limits** for every category (including custom categories). The overall
limit replaces the disposable-income figure for pay-period pacing when set;
otherwise the old income − savings − fixed-cost calculation is used. Each
category shows a progress bar with a warning at **80%** and an over-limit state
at **100%**. The page also shows **spending by wallet** for the selected month,
with each amount in that wallet's currency and unassigned spending shown
separately.

**Recurring transactions** (Settings → 定期取引, route `/recurring`) post rent,
subscriptions and fixed income automatically. Each item has a direction
(expense/income), amount, currency, category, wallet, daily/weekly/monthly cycle
and payday anchor, start date and active flag. On app launch/resume, due
occurrences are written into the normal receipts or income collections with a
`recurring_id`, and `last_posted_at` prevents posting the same cycle twice. The
UI also has a **Post due now** action. Future recurring **expenses** due before
the next payday are subtracted in the dashboard **After obligations** number;
posted transactions already affect wallet balances, so they are not counted
twice. Inactive recurring items are skipped.

Settings → **Data** → **Export all data as CSV** writes one UTF-8 CSV with a
`record_type` column containing wallets, transactions (receipts, income,
transfers, adjustments) and definitions for income sources, debts, debt
repayments and recurring transactions.

### Duplicate detection and amount checks

A Japanese receipt prints two different numbers that look similar:

| Printed value | Example | Meaning |
| --- | --- | --- |
| 登録番号 / qualified invoice registration number | `T8012402001708` | Identifies the **business**. Repeats on every receipt from that shop. |
| 伝票番号 / レシート番号 / receipt barcode | `0100000001` | Identifies **this purchase**. |

The receipt number is the duplicate key and is stored in `receipt_number` (the
legacy `barcode_id` field is still read and kept in sync for older builds). The
registration number is stored separately in `invoice_registration_number` and
is **never** used for duplicate detection. Legacy documents whose `barcode_id`
is a `T` + 13 digit value are normalised on read and moved to the invoice field
by a one-time, non-blocking migration.

Coupon barcodes and `No.` values printed under クーポン / 利用期限 are ignored. If
the receipt has no own number, the fallback fingerprint is **merchant +
purchased_at to the minute + total**. When a duplicate is found, the review
screen shows the existing receipt's merchant, date and total, with **Open** and
**Save anyway** (false positives are allowed).

Item totals are checked against the printed **tax-excluded subtotal** when one
exists. A receipt is consistent when `sum(items) == subtotal`, when
`sum(items) + tax == total`, or when the line prices are tax-included and
`sum(items) == total`; the warning appears only when none of those match. This
handles receipts such as items 170 + 41 = 211, tax 16, total 227.

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
│   ├── settings/                   # persisted salary-cycle preference
│   ├── theme/                      # Material 3 light/dark
│   ├── utils/                      # money/date formatting, barcode checks
│   └── widgets/                    # language switcher, press scale, budget bar
├── domain/
│   ├── models/                     # receipt, item, category, budget, pay cycle, filter
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
    ├── dashboard/ receipts/ categories/ budget/ payments/
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
| `shared_preferences` | Theme + language + salary-cycle preferences, coupon action journal / reminder state |
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
change amounts, 8%/10% tax lines, tax-inclusive bases, receipt vs registration
numbers, coupon-number exclusion, duplicate fingerprints, the subtotal/tax item
check and line-item extraction. Income tests cover source JSON round-trips,
monthly-equivalent conversion, paydays inside a period, the single budget-period
flag, legacy migration, period income totals and free-text source suggestions.
Wallet tests cover computed balances, cross-currency transfers, credit-card
owed/available and due dates, include-in-total rules, the three dashboard totals
and old documents. FX tests cover cached/manual/missing rates, conversion and
the six-hour cache window. Debt tests cover repayment math, status transitions,
wallet movements, reminder windows and `.ics` generation. Phase 4 tests cover
budget limit parsing, the 80%/100% thresholds, per-wallet spending, recurring
occurrence generation and the full CSV export.

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
   extracted item table. A duplicate receipt number (or merchant + minute +
   total) shows the existing receipt and blocks saving unless **Save anyway**
   is chosen; 登録番号 values never block saving.
7. **Save** — only receipt JSON + items are written to
   `users/{uid}/receipts/{receiptId}`. The in-memory image reference is dropped
   when the screen closes or the receipt is saved.

---

## Languages

On startup the app uses the **browser / system language**
(`navigator.languages` on web, the OS locale elsewhere) when it is one of
**日本語 / English / العربية**; anything else falls back to Japanese. The
globe button in every header — including the login (`/login`, `/auth`) and
register (`/register`) screens — switches the language instantly. A manual
choice is stored in `SharedPreferences` and overrides the browser default on
later visits. Arabic switches the whole UI to RTL and date formatting uses the
selected locale.
