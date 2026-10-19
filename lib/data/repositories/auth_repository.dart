import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';

class AuthRepository {
  AuthRepository([this._client]);

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  User? get currentUser => AppConfig.isLocal ? null : _supabase.auth.currentUser;

  Session? get currentSession =>
      AppConfig.isLocal ? null : _supabase.auth.currentSession;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    if (AppConfig.isLocal) {
      return Future<AuthResponse>.value(AuthResponse());
    }
    return _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    if (AppConfig.isLocal) {
      return Future<AuthResponse>.value(AuthResponse());
    }
    return _supabase.auth.signUp(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() async {
    if (AppConfig.isLocal) return;
    await _supabase.auth.signOut();
  }

  Future<void> sendPasswordReset(String email) async {
    if (AppConfig.isLocal) return;
    await _supabase.auth.resetPasswordForEmail(email.trim());
  }

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