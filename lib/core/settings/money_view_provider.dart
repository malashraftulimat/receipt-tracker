import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which headline the dashboard money card shows.
enum MoneyView { available, afterObligations, netWorth }

extension MoneyViewLabels on MoneyView {
  String get label => switch (this) {
        MoneyView.available => 'money.available',
        MoneyView.afterObligations => 'money.after_obligations',
        MoneyView.netWorth => 'money.net_worth',
      };
}

/// Remember the user's segmented-control choice across sessions/devices.
class MoneyViewController extends Notifier<MoneyView> {
  static const String _prefsKey = 'money_view';

  @override
  MoneyView build() {
    Future<void>(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        for (final view in MoneyView.values) {
          if (view.name == raw) {
            state = view;
            break;
          }
        }
      } catch (_) {
        // Storage unavailable — keep the default.
      }
    });
    return MoneyView.available;
  }

  Future<void> setView(MoneyView view) async {
    state = view;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, view.name);
    } catch (_) {
      // Persisting failed; the choice still applies for this session.
    }
  }
}

final moneyViewProvider =
    NotifierProvider<MoneyViewController, MoneyView>(MoneyViewController.new);
