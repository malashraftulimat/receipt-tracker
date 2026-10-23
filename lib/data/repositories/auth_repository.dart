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
          return 'auth.invalid_email';
        case 'user-disabled':
          return 'auth.account_disabled';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'auth.wrong_credentials';
        case 'email-already-in-use':
          return 'auth.email_in_use';
        case 'weak-password':
          return 'auth.weak_password_repo';
        case 'too-many-requests':
          return 'auth.too_many_requests';
        case 'operation-not-allowed':
          return 'auth.provider_disabled';
        case 'network-request-failed':
          return 'auth.network_error';
        case 'requires-recent-login':
          return 'auth.require_recent_login';
      }
      return error.message ?? 'auth.failed_repo';
    }
    return 'auth.network_error';
  }
}
