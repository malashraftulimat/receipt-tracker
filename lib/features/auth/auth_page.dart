import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../data/providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../core/localization/localization.dart';

enum _AuthMode { signIn, signUp }

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key, this.initialSignUp = false});

  /// Opens the register form straight away (used by the `/register` route).
  final bool initialSignUp;

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialSignUp) _mode = _AuthMode.signUp;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final repository = ref.read(authRepositoryProvider);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final isSignUp = _mode == _AuthMode.signUp;

    try {
      if (!isSignUp) {
        await repository.signIn(email: email, password: password);
      } else {
        await repository.signUp(
          email: email,
          password: password,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = AuthRepository.describeError(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'パスワード再設定にはメールアドレスを入力してください。');
      return;
    }
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (!mounted) return;
      _showMessage('パスワード再設定メールを送信しました。');
    } catch (error) {
      if (mounted) {
        setState(() => _error = AuthRepository.describeError(error));
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: AppText(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSignUp = _mode == _AuthMode.signUp;

    return Scaffold(
      appBar: AppBar(
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(context.pagePadding * 2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(
                  Icons.receipt_long,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                AppText(
                  'レシート帳',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                AppText(
                  '紙のレシートをスキャンして、支出をかしこく管理',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                SegmentedButton<_AuthMode>(
                  segments: const <ButtonSegment<_AuthMode>>[
                    ButtonSegment<_AuthMode>(
                      value: _AuthMode.signIn,
                      label: AppText('ログイン'),
                    ),
                    ButtonSegment<_AuthMode>(
                      value: _AuthMode.signUp,
                      label: AppText('新規登録'),
                    ),
                  ],
                  selected: <_AuthMode>{_mode},
                  onSelectionChanged: (selection) => setState(() {
                    _mode = selection.first;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 20),
                Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      children: <Widget>[
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const <String>[AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: context.tr('メールアドレス'),
                            prefixIcon: const Icon(Icons.mail_outline),
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) {
                              return context.tr('メールアドレスを入力してください');
                            }
                            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(text)) {
                              return context.tr('メールアドレスの形式が正しくありません');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          autofillHints: <String>[
                            isSignUp
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: context.tr('パスワード'),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').length < 6) {
                              return context.tr('パスワードは6文字以上で入力してください');
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.error_outline,
                          size: 18,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppText(
                            _error!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : AppText(isSignUp ? 'アカウントを作成' : 'ログイン'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading ? null : _resetPassword,
                  child: const AppText('パスワードを忘れた場合'),
                ),
                const SizedBox(height: 8),
                AppText(
                  'レシートデータはアカウントに紐づけて暗号化保存され、'
                  'すべての端末で同期されます。写真は保存されません。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
