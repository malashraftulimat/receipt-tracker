import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../domain/models/exchange_rates.dart';

/// Local cache for exchange rates and manual overrides.
///
/// Rates are cached for about six hours and reused offline. Manual overrides
/// never expire; they always win over fetched rates.
class FxStore {
  const FxStore._();

  static const String _cachePrefix = 'fx_cache_v1_';
  static const String _overridesKey = 'fx_manual_overrides_v1';

  static String _cacheKey(String base) =>
      '$_cachePrefix${base.trim().toUpperCase()}';

  static Future<FxSnapshot?> readCache(String base) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(base));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return FxSnapshot.fromCacheJson(decoded, base: base);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeCache(FxSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey(snapshot.base),
        jsonEncode(snapshot.toCacheJson()),
      );
    } catch (_) {
      // Cache failure is not fatal; the snapshot in memory still works.
    }
  }

  static Future<Map<String, double>> readOverrides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_overridesKey);
      if (raw == null) return <String, double>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, double>{};
      final result = <String, double>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is num) {
          result[entry.key.toString()] = value.toDouble();
        }
      }
      return result;
    } catch (_) {
      return <String, double>{};
    }
  }

  static Future<void> writeOverrides(Map<String, double> overrides) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_overridesKey, jsonEncode(overrides));
    } catch (_) {
      // Keep the in-memory value for this session.
    }
  }
}
