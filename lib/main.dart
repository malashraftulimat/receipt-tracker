import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Japanese date formatting (yyyy年M月d日(E)).
  await initializeDateFormatting('ja');

  // Connect to Supabase with dart-defines or previously saved credentials.
  // When neither exists, the app opens the "接続設定" screen.
  final prefs = await SharedPreferences.getInstance();
  await AppConfig.bootstrap(prefs);

  runApp(const ProviderScope(child: ReceiptTrackerApp()));
}
