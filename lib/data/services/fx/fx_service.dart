import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../domain/models/exchange_rates.dart';
import 'fx_store.dart';

/// Fetches exchange rates from Frankfurter (v2) and falls back to
/// open.er-api.com when a currency is not served or Frankfurter is unavailable.
///
/// Both endpoints support browser CORS. The result is cached locally for about
/// six hours. Rates are used for **display only** and are never stored with a
/// transaction.
class FxService {
  FxService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void dispose() => _client.close();

  static const String _frankfurterBase = 'https://api.frankfurter.dev/v2';
  static const String _erApiBase = 'https://open.er-api.com/v6/latest';

  Future<FxSnapshot> load({
    required String base,
    bool forceRefresh = false,
  }) async {
    final code = base.trim().toUpperCase();
    final cached = await FxStore.readCache(code);
    if (!forceRefresh &&
        cached != null &&
        isFxCacheFresh(cached.fetchedAt)) {
      return cached;
    }

    final fetched = await _fetch(code);
    if (fetched != null) {
      final snapshot = FxSnapshot(
        base: code,
        rates: fetched.rates,
        fetchedAt: DateTime.now(),
        source: fetched.source,
      );
      await FxStore.writeCache(snapshot);
      return snapshot;
    }

    if (cached != null) {
      return FxSnapshot(
        base: cached.base,
        rates: cached.rates,
        fetchedAt: cached.fetchedAt,
        source: cached.source,
        fromCache: true,
        stale: true,
      );
    }

    return FxSnapshot(
      base: code,
      rates: const <String, double>{},
      fetchedAt: DateTime.now(),
      source: FxSource.none,
    );
  }

  Future<({Map<String, double> rates, FxSource source})?> _fetch(
    String base,
  ) async {
    final frankfurter = await _fetchFrankfurter(base);
    if (frankfurter != null && frankfurter.isNotEmpty) {
      final erApi = await _fetchErApi(base);
      final merged = <String, double>{
        if (erApi != null) ...erApi,
        ...frankfurter,
      };
      return (rates: merged, source: FxSource.frankfurter);
    }
    final erApi = await _fetchErApi(base);
    if (erApi != null && erApi.isNotEmpty) {
      return (rates: erApi, source: FxSource.erApi);
    }
    return null;
  }

  Future<Map<String, double>?> _fetchFrankfurter(String base) async {
    try {
      final uri = Uri.parse('$_frankfurterBase/rates?base=$base');
      final response = await _client.get(uri).timeout(
            const Duration(seconds: 10),
          );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) return null;
      final rates = <String, double>{base: 1};
      for (final row in decoded) {
        if (row is! Map) continue;
        final quote = row['quote']?.toString().toUpperCase();
        final rate = row['rate'];
        if (quote == null || quote.isEmpty || rate is! num) continue;
        rates[quote] = rate.toDouble();
      }
      return rates.length > 1 ? rates : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, double>?> _fetchErApi(String base) async {
    try {
      final uri = Uri.parse('$_erApiBase/$base');
      final response = await _client.get(uri).timeout(
            const Duration(seconds: 10),
          );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['result'] != 'success') return null;
      final rawRates = decoded['rates'];
      if (rawRates is! Map) return null;
      final rates = <String, double>{};
      for (final entry in rawRates.entries) {
        final value = entry.value;
        if (value is num) {
          rates[entry.key.toString().toUpperCase()] = value.toDouble();
        }
      }
      rates[base] = 1;
      return rates.length > 1 ? rates : null;
    } catch (_) {
      return null;
    }
  }
}
