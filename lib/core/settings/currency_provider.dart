import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../localization/currencies.dart';

/// Persisted default currency (ISO 4217 code).
///
/// Defaults to JPY so existing users keep the previous behaviour. The choice is
/// local to the device, like the theme, language and salary-cycle preferences.
class CurrencyController extends Notifier<Currency> {
  static const String _prefsKey = 'default_currency';

  @override
  Currency build() {
    Future<void>(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = currencyByCode(prefs.getString(_prefsKey));
        if (saved != null && saved.code != state.code) state = saved;
      } catch (_) {
        // Storage unavailable (e.g. unit tests) — keep the default.
      }
    });
    return kFallbackCurrency;
  }

  Future<void> setCurrency(Currency currency) async {
    state = currency;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, currency.code);
    } catch (_) {
      // Persisting failed; the in-memory choice still applies for this session.
    }
  }

  Future<void> setCode(String code) async {
    final currency = currencyByCode(code);
    if (currency != null) await setCurrency(currency);
  }
}

final defaultCurrencyProvider =
    NotifierProvider<CurrencyController, Currency>(CurrencyController.new);

/// Convenience code for widgets that only need the ISO string.
final defaultCurrencyCodeProvider = Provider<String>(
  (ref) => ref.watch(defaultCurrencyProvider).code,
);
