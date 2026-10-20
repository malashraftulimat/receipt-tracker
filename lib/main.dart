import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/config/firebase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Date symbols for every UI language (Japanese / English / Arabic).
  await initializeDateFormatting('ja');
  await initializeDateFormatting('en');
  await initializeDateFormatting('ar');

  // Firebase Auth + Cloud Firestore (Web / Android / iOS).
  await Firebase.initializeApp(options: kFirebaseOptions);

  runApp(const ProviderScope(child: ReceiptTrackerApp()));
}
