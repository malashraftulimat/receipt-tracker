/// Minimal, backend-agnostic user used by the UI.
///
/// Firebase Auth users are mapped to this minimal, UI-friendly type.
class AppUser {
  const AppUser({required this.id, required this.email});

  final String id;
  final String email;
}