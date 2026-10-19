import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/responsive.dart';
import '../../data/services/local_store.dart';

/// First-launch screen for builds that were not compiled with
/// `--dart-define=SUPABASE_URL/...` (e.g. a sideloaded APK or a web bundle).
class ConnectionSetupPage extends StatefulWidget {
  const ConnectionSetupPage({super.key});

  @override
  State<ConnectionSetupPage> createState() => _ConnectionSetupPageState();
}

class _ConnectionSetupPageState extends State<ConnectionSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _startLocalMode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await LocalStore.instance.seedDefaults();
      await AppConfig.useLocalMode(prefs);
      if (!mounted) return;
      runApp(const ProviderScope(child: ReceiptTrackerApp()));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _connect() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await AppConfig.connect(
        url: _urlController.text,
        anonKey: _keyController.text,
        prefs: prefs,
      );
      if (!mounted) return;
      // Re-bootstrap the whole app with the freshly initialised client.
      runApp(const ProviderScope(child: ReceiptTrackerApp()));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(context.pagePadding * 1.5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(
                    Icons.receipt_long,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'レシート帳',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'はじめに Supabase プロジェクトへ接続します。\n'
                    'レシート・画像・カテゴリはこのプロジェクトに保存され、'
                    'すべての端末で同期されます。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 26),
                  TextFormField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Project URL',
                      hintText: 'https://xxxx.supabase.co',
                      prefixIcon: Icon(Icons.link),
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) return 'Project URL を入力してください';
                      if (!text.startsWith('https://') &&
                          !text.startsWith('http://')) {
                        return 'https:// から始まる URL を入力してください';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _keyController,
                    obscureText: _obscure,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'anon / publishable key',
                      hintText: 'eyJhbGciOi... または sb_publishable_...',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        tooltip: '表示を切り替え',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'anon / publishable key を入力してください'
                        : null,
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_done_outlined),
                    label: Text(_busy ? '接続しています…' : '接続して開始'),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _startLocalMode,
                    icon: const Icon(Icons.phone_android),
                    label: const Text('アカウントなしで使う（この端末に保存）'),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '値の取得場所',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Supabase ダッシュボード → Project Settings → API の '
                          '「Project URL」と「anon public / publishable key」。\n'
                          'これらのキーはクライアント公開前提の値です。'
                          'テーブルは supabase/schema.sql で作成してください。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
