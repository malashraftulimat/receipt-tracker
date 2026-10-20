/// reCAPTCHA v3 site key registered for this web app in
/// Firebase Console → App Check → Apps → Manage reCAPTCHA keys.
///
/// Pass it at build time so GitHub Pages keeps working without committing a
/// key (the app simply skips App Check activation when it is empty):
///
/// ```bash
/// flutter build web --release \
///   --base-href=/receipt-tracker/ \
///   --dart-define=RECAPTCHA_V3_SITE_KEY=6L...
/// ```
const String kReCaptchaV3SiteKey = String.fromEnvironment(
  'RECAPTCHA_V3_SITE_KEY',
);
