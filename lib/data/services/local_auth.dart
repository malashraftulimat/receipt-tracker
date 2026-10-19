import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/app_user.dart';

/// Email/password accounts that live entirely on this device (local mode).
///
/// Passwords are salted and hashed with SHA-256 before being stored. This is
/// deliberately simple (no server, no PBKDF2) and intended for a personal,
/// single-device tool — use Supabase auth for anything stronger.
class LocalAuth {
  LocalAuth._();

  static final LocalAuth instance = LocalAuth._();

  static const String usersKey = 'local_users_v1';
  static const String sessionKey = 'local_session_v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Test hook.
  void resetCacheForTests() {
    _prefs = null;
  }

  Future<List<Map<String, dynamic>>> _readUsers() async {
    final prefs = await _p;
    final raw = prefs.getString(usersKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }
    } catch (_) {
      // Ignore corrupted payloads.
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> _writeUsers(List<Map<String, dynamic>> users) async {
    final prefs = await _p;
    await prefs.setString(usersKey, jsonEncode(users));
  }

  /// Returns the persisted session user, if any.
  Future<AppUser?> restoreSession() async {
    final prefs = await _p;
    final userId = prefs.getString(sessionKey);
    if (userId == null) return null;
    for (final user in await _readUsers()) {
      if (user['id'] == userId) {
        return AppUser(id: userId, email: user['email'] as String);
      }
    }
    return null;
  }

  Future<AppUser> signUp({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      throw const LocalAuthException('メールアドレスの形式が正しくありません。');
    }
    if (password.length < 6) {
      throw const LocalAuthException('パスワードは6文字以上で入力してください。');
    }

    final users = await _readUsers();
    if (users.any((user) => user['email'] == normalized)) {
      throw const LocalAuthException('このメールアドレスは既に登録されています。');
    }

    final salt = _randomSalt();
    final user = <String, dynamic>{
      'id': 'u-${DateTime.now().microsecondsSinceEpoch}',
      'email': normalized,
      'salt': salt,
      'hash': _hash(password, salt),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    users.add(user);
    await _writeUsers(users);

    final prefs = await _p;
    await prefs.setString(sessionKey, user['id'] as String);
    return AppUser(id: user['id'] as String, email: normalized);
  }

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    final users = await _readUsers();

    for (final user in users) {
      if (user['email'] != normalized) continue;
      final expected = _hash(password, user['salt'] as String);
      if (user['hash'] != expected) {
        throw const LocalAuthException('メールアドレスまたはパスワードが違います。');
      }
      final prefs = await _p;
      await prefs.setString(sessionKey, user['id'] as String);
      return AppUser(id: user['id'] as String, email: normalized);
    }

    throw const LocalAuthException('メールアドレスまたはパスワードが違います。');
  }

  Future<void> signOut() async {
    final prefs = await _p;
    await prefs.remove(sessionKey);
  }

  /// Deletes the account (used by "ローカルデータを削除").
  Future<void> deleteAccount(String userId) async {
    final users = await _readUsers();
    users.removeWhere((user) => user['id'] == userId);
    await _writeUsers(users);
    final prefs = await _p;
    if (prefs.getString(sessionKey) == userId) {
      await prefs.remove(sessionKey);
    }
  }

  Future<int> accountCount() async => (await _readUsers()).length;

  String _randomSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();
}

class LocalAuthException implements Exception {
  const LocalAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}