import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/services/fx/fx_store.dart';
import 'package:receipt_tracker/domain/models/exchange_rates.dart';
import 'package:shared_preferences/shared_preferences.dart';

FxSnapshot snapshot({
  Map<String, double>? rates,
  Map<String, double>? overrides,
  DateTime? fetchedAt,
}) {
  return FxSnapshot(
    base: 'JPY',
    rates: rates ??
        <String, double>{
          'USD': 1 / 150,
          'EUR': 1 / 160,
          'GBP': 1 / 190,
        },
    fetchedAt: fetchedAt ?? DateTime(2026, 10, 25, 9),
    source: FxSource.frankfurter,
    overrides: overrides ?? const <String, double>{},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FX conversion', () {
    test('converts through the display base and across currencies', () {
      final fx = snapshot();
      expect(fx.rateFor('USD', 'JPY'), closeTo(150, 0.0001));
      expect(fx.rateFor('JPY', 'USD'), closeTo(1 / 150, 1e-9));
      expect(
        fx.rateFor('USD', 'EUR'),
        closeTo((1 / 160) / (1 / 150), 1e-9),
      );
      expect(fx.convert(100, 'USD', 'JPY'), closeTo(15000, 0.01));
      expect(fx.convert(5, 'USD', 'USD'), 5);
    });

    test('manual rate always wins, including its inverse', () {
      final fx = snapshot(
        overrides: <String, double>{'USD>JPY': 155},
      );
      expect(fx.isManual('USD', 'JPY'), isTrue);
      expect(fx.isManual('JPY', 'USD'), isTrue);
      expect(fx.rateFor('USD', 'JPY'), 155);
      expect(fx.rateFor('JPY', 'USD'), closeTo(1 / 155, 1e-9));
      expect(fx.convert(100, 'USD', 'JPY'), 15500);
      expect(fx.isManual('EUR', 'JPY'), isFalse);
    });

    test('a missing rate returns null instead of guessing', () {
      final fx = snapshot(rates: <String, double>{'USD': 1 / 150});
      expect(fx.rateFor('EUR', 'JPY'), isNull);
      expect(fx.convert(10, 'EUR', 'JPY'), isNull);
      // Same currency needs no rate.
      expect(fx.convert(10, 'EUR', 'EUR'), 10);
    });

    test('cache JSON round trip keeps the fetch time and source', () {
      final original = snapshot();
      final restored = FxSnapshot.fromCacheJson(
        original.toCacheJson(),
        base: 'JPY',
      );
      expect(restored.base, 'JPY');
      expect(restored.source, FxSource.frankfurter);
      expect(restored.fromCache, isTrue);
      expect(restored.fetchedAt, original.fetchedAt);
      expect(restored.rateFor('USD', 'JPY'), closeTo(150, 0.0001));
    });

    test('cache is fresh for about six hours', () {
      final fetched = DateTime(2026, 10, 25, 9);
      expect(
        isFxCacheFresh(fetched, now: DateTime(2026, 10, 25, 14)),
        isTrue,
      );
      expect(
        isFxCacheFresh(fetched, now: DateTime(2026, 10, 25, 15, 1)),
        isFalse,
      );
    });
  });

  group('FX local store', () {
    test('manual overrides survive a read/write round trip', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await FxStore.writeOverrides(<String, double>{
        'USD>JPY': 155,
        'EUR>JPY': 165,
      });
      final restored = await FxStore.readOverrides();
      expect(restored['USD>JPY'], 155);
      expect(restored['EUR>JPY'], 165);
    });

    test('rate cache survives a read/write round trip', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final original = snapshot();
      await FxStore.writeCache(original);
      final restored = await FxStore.readCache('JPY');
      expect(restored, isNotNull);
      expect(restored!.rateFor('USD', 'JPY'), closeTo(150, 0.0001));
      expect(restored.fromCache, isTrue);
    });

    test('manual overrides are applied on top of a cached snapshot', () {
      final cached = snapshot();
      final withOverride = cached.withOverrides(<String, double>{
        'USD>JPY': 152,
      });
      expect(withOverride.rateFor('USD', 'JPY'), 152);
      expect(withOverride.rateFor('EUR', 'JPY'), closeTo(160, 0.0001));
    });
  });
}
