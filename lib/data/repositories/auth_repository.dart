import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  Session? get currentSession => _client.auth.currentSession;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      _client.auth.resetPasswordForEmail(email.trim());

  /// Human readable (Japanese) message for auth failures.
  static String describeError(Object error) {
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login credentials')) {
        return 'メールアドレスまたはパスワードが違います。';
      }
      if (message.contains('email not confirmed')) {
        return 'メールアドレスが未確認です。確認メールをご確認ください。';
      }
      if (message.contains('already registered') ||
          message.contains('user already exists')) {
        return 'このメールアドレスは既に登録されています。';
      }
      if (error.statusCode == '429' || message.contains('rate limit')) {
        return '試行回数が多すぎます。しばらく待ってから再試行してください。';
      }
      if (message.contains('password should be at least')) {
        return 'パスワードは6文字以上で入力してください。';
      }
      return error.message;
    }
    return '通信に失敗しました。ネットワークを確認してください。';
  }
}
