/// Where a rate table came from.
enum FxSource { frankfurter, erApi, none }

/// A rate table for one display currency.
///
/// [rates] are quoted as `1 base = rates[quote]`. Manual overrides are kept in
/// the same snapshot and **always win** over fetched/cached rates.
class FxSnapshot {
  const FxSnapshot({
    required this.base,
    required this.rates,
    required this.fetchedAt,
    this.source = FxSource.none,
    this.overrides = const <String, double>{},
    this.fromCache = false,
    this.stale = false,
  });

  final String base;
  final Map<String, double> rates;
  final DateTime fetchedAt;
  final FxSource source;

  /// Keys are `FROM>TO`, e.g. `USD>JPY`.
  final Map<String, double> overrides;

  /// True when this snapshot was served from the local 6-hour cache.
  final bool fromCache;

  /// True when the cache is older than the normal refresh window and the
  /// network was unavailable.
  final bool stale;

  bool get hasRates => rates.isNotEmpty || overrides.isNotEmpty;

  static String pairKey(String from, String to) =>
      '${from.trim().toUpperCase()}>${to.trim().toUpperCase()}';

  /// A manual override for this exact pair, or its inverse.
  double? manualRateFor(String from, String to) {
    final upperFrom = from.trim().toUpperCase();
    final upperTo = to.trim().toUpperCase();
    if (upperFrom == upperTo) return 1;
    final direct = overrides[pairKey(upperFrom, upperTo)];
    if (direct != null && direct > 0) return direct;
    final inverse = overrides[pairKey(upperTo, upperFrom)];
    if (inverse != null && inverse > 0) return 1 / inverse;
    return null;
  }

  bool isManual(String from, String to) {
    final upperFrom = from.trim().toUpperCase();
    final upperTo = to.trim().toUpperCase();
    if (upperFrom == upperTo) return false;
    return overrides.containsKey(pairKey(upperFrom, upperTo)) ||
        overrides.containsKey(pairKey(upperTo, upperFrom));
  }

  /// Converts [amount] from one currency to another.
  ///
  /// Returns `null` when no manual override and no fetched rate is available.
  /// Callers must show the wallet in its own currency and exclude it from the
  /// converted total rather than guessing.
  double? convert(double amount, String from, String to) {
    final rate = rateFor(from, to);
    return rate == null ? null : amount * rate;
  }

  double? rateFor(String from, String to) {
    final upperFrom = from.trim().toUpperCase();
    final upperTo = to.trim().toUpperCase();
    if (upperFrom == upperTo) return 1;

    final manual = manualRateFor(upperFrom, upperTo);
    if (manual != null) return manual;

    final fromRate = rates[upperFrom];
    final toRate = rates[upperTo];

    if (upperFrom == base.trim().toUpperCase()) {
      return toRate;
    }
    if (upperTo == base.trim().toUpperCase()) {
      if (fromRate == null || fromRate == 0) return null;
      return 1 / fromRate;
    }
    if (fromRate == null || toRate == null || fromRate == 0) return null;
    return toRate / fromRate;
  }

  FxSnapshot withOverrides(Map<String, double> nextOverrides) => FxSnapshot(
        base: base,
        rates: rates,
        fetchedAt: fetchedAt,
        source: source,
        overrides: Map<String, double>.unmodifiable(nextOverrides),
        fromCache: fromCache,
        stale: stale,
      );

  /// Local-cache JSON. Manual overrides are stored separately.
  Map<String, dynamic> toCacheJson() => <String, dynamic>{
        'fetched_at': fetchedAt.toUtc().toIso8601String(),
        'source': source.name,
        'rates': rates,
      };

  factory FxSnapshot.fromCacheJson(
    Map<String, dynamic> json, {
    required String base,
  }) {
    final rawRates = json['rates'];
    final parsed = <String, double>{};
    if (rawRates is Map) {
      for (final entry in rawRates.entries) {
        final value = entry.value;
        if (value is num) {
          parsed[entry.key.toString().toUpperCase()] = value.toDouble();
        }
      }
    }
    return FxSnapshot(
      base: base.trim().toUpperCase(),
      rates: parsed,
      fetchedAt:
          DateTime.tryParse(json['fetched_at']?.toString() ?? '')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
      source: _sourceFromName(json['source']),
      fromCache: true,
    );
  }

  static FxSource _sourceFromName(Object? raw) {
    for (final source in FxSource.values) {
      if (source.name == raw) return source;
    }
    return FxSource.none;
  }
}

/// Cache is reused for six hours before a network refresh is attempted.
const Duration kFxCacheMaxAge = Duration(hours: 6);

bool isFxCacheFresh(DateTime fetchedAt, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final age = current.difference(fetchedAt);
  return !age.isNegative && age < kFxCacheMaxAge;
}
