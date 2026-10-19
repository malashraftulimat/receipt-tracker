/// Minimal, backend-agnostic user used by the UI.
///
/// Supabase sessions are mapped to this type, and local mode uses a synthetic
/// on-device user so the exact same widgets work without an account.
class AppUser {
  const AppUser({required this.id, required this.email});

  final String id;
  final String email;
}