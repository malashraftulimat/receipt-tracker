import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/pay_cycle.dart';

/// Persisted "how my salary arrives" preference (daily / weekly / monthly).
///
/// Stored locally in `SharedPreferences`, next to the theme and language
/// preferences, so the budget can be paced without an extra network round
/// trip. The monthly amounts themselves stay in Firestore.
class PayCycleController extends Notifier<PayCycleConfig> {
  static const String _prefsKey = 'pay_cycle';

  @override
  PayCycleConfig build() {
    Future<void>(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw == null) return;
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          state = PayCycleConfig.fromJson(decoded);
        }
      } catch (_) {
        // Storage unavailable (e.g. unit tests) — keep the default (monthly).
      }
    });
    return PayCycleConfig.defaults;
  }

  Future<void> setCycle(PayCycle cycle) => _update(state.copyWith(cycle: cycle));

  Future<void> setWeeklyStartWeekday(int weekday) =>
      _update(state.copyWith(weeklyStartWeekday: weekday));

  Future<void> setMonthlyPayDay(int day) =>
      _update(state.copyWith(monthlyPayDay: day));

  Future<void> _update(PayCycleConfig next) async {
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(next.toJson()));
    } catch (_) {
      // Persisting failed; the in-memory choice still applies for this session.
    }
  }
}

final payCycleProvider =
    NotifierProvider<PayCycleController, PayCycleConfig>(
  PayCycleController.new,
);
