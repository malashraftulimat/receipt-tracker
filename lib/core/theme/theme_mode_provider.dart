import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted light / dark / system preference.
class ThemeModeController extends Notifier<ThemeMode> {
  static const String _prefsKey = 'theme_mode';

  @override
  ThemeMode build() {
    // Fire-and-forget restore; the vibrant dark theme is the default until a
    // saved preference resolves.
    Future<void>(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getString(_prefsKey);
        if (stored == null) return;
        for (final mode in ThemeMode.values) {
          if (mode.name == stored) state = mode;
        }
      } catch (_) {
        // Storage unavailable (e.g. unit tests) — keep the default.
      }
    });
    return ThemeMode.dark;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
