import 'package:firebase_auth/firebase_auth.dart';

/// Firebase Email/Password authentication.
class AuthRepository {
  AuthRepository([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  FirebaseAuth get auth => _auth;

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  /// Human readable (Japanese) message for Firebase Auth failures.
  static String describeError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'メールアドレスの形式が正しくありません。';
        case 'user-disabled':
          return 'このアカウントは無効化されています。';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'メールアドレスまたはパスワードが違います。';
        case 'email-already-in-use':
          return 'このメールアドレスは既に登録されています。';
        case 'weak-password':
          return 'パスワードは6文字以上で入力してください。';
        case 'too-many-requests':
          return '試行回数が多すぎます。しばらく待ってから再試行してください。';
        case 'operation-not-allowed':
          return 'メール/パスワード認証が Firebase で有効になっていません。';
        case 'network-request-failed':
          return '通信に失敗しました。ネットワークを確認してください。';
        case 'requires-recent-login':
          return '再度ログインしてから操作してください。';
      }
      return error.message ?? '認証に失敗しました。';
    }
    return '通信に失敗しました。ネットワークを確認してください。';
  }
}
