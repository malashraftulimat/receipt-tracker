/// Built-in Supabase project for the hosted web build.
///
/// Two ways to provide the values:
///   1. Edit the two constants below (replace the placeholders) and push.
///   2. Build with `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
///      (the GitHub Pages workflow does this from repository secrets).
///
/// When these are usable, the app connects automatically on launch and shows
/// the login screen instead of the manual "接続して開始" setup screen.
class SupabaseDefaults {
  const SupabaseDefaults._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR-PROJECT.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR-ANON-KEY',
  );

  static bool get isUsable =>
      url.startsWith('https://') &&
      !url.contains('YOUR-PROJECT') &&
      anonKey.length > 20 &&
      !anonKey.contains('YOUR-ANON');
}