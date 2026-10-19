import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/services/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalAuth.instance.resetCacheForTests();
  });

  test('signs up and restores the session', () async {
    final user = await LocalAuth.instance.signUp(
      email: 'Test@Example.com',
      password: 'secret123',
    );
    expect(user.email, 'test@example.com');
    expect(user.id, startsWith('u-'));

    final restored = await LocalAuth.instance.restoreSession();
    expect(restored?.id, user.id);
    expect(await LocalAuth.instance.accountCount(), 1);
  });

  test('rejects duplicate emails and weak passwords', () async {
    await LocalAuth.instance.signUp(
      email: 'a@example.com',
      password: 'secret123',
    );

    await expectLater(
      LocalAuth.instance.signUp(
        email: 'A@example.com',
        password: 'another123',
      ),
      throwsA(isA<LocalAuthException>()),
    );
    await expectLater(
      LocalAuth.instance.signUp(email: 'b@example.com', password: '123'),
      throwsA(isA<LocalAuthException>()),
    );
    await expectLater(
      LocalAuth.instance.signUp(
        email: 'not-an-email',
        password: 'secret123',
      ),
      throwsA(isA<LocalAuthException>()),
    );
  });

  test('sign in checks the password', () async {
    await LocalAuth.instance.signUp(
      email: 'a@example.com',
      password: 'secret123',
    );
    await LocalAuth.instance.signOut();
    expect(await LocalAuth.instance.restoreSession(), isNull);

    await expectLater(
      LocalAuth.instance.signIn(email: 'a@example.com', password: 'wrong'),
      throwsA(isA<LocalAuthException>()),
    );

    final user = await LocalAuth.instance.signIn(
      email: ' a@example.com ',
      password: 'secret123',
    );
    expect(user.email, 'a@example.com');
    expect((await LocalAuth.instance.restoreSession())?.id, user.id);
  });

  test('does not store the password in plain text', () async {
    await LocalAuth.instance.signUp(
      email: 'a@example.com',
      password: 'secret123',
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(LocalAuth.usersKey) ?? '';
    expect(raw.contains('secret123'), isFalse);
    expect(raw.contains('"hash"'), isTrue);
  });

  test('deleteAccount removes the user and session', () async {
    final user = await LocalAuth.instance.signUp(
      email: 'a@example.com',
      password: 'secret123',
    );
    await LocalAuth.instance.deleteAccount(user.id);
    expect(await LocalAuth.instance.accountCount(), 0);
    expect(await LocalAuth.instance.restoreSession(), isNull);
  });
}