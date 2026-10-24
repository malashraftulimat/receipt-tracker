import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/fx/fx_service.dart';
import '../../data/services/fx/fx_store.dart';
import '../../domain/models/exchange_rates.dart';
import 'currency_provider.dart';

final fxServiceProvider = Provider<FxService>((ref) {
  final service = FxService();
  ref.onDispose(service.dispose);
  return service;
});

/// Raw rate table + the manual overrides currently applied on top of it.
class FxState {
  const FxState({
    required this.snapshot,
    required this.overrides,
  });

  final FxSnapshot snapshot;

  /// Keys are `FROM>TO`.
  final Map<String, double> overrides;
}

/// Loads the display-currency rate table (6-hour cache) and manual overrides.
class ExchangeRatesController extends AsyncNotifier<FxState> {
  @override
  Future<FxState> build() async {
    final base = ref.watch(defaultCurrencyProvider).code;
    final overrides = await FxStore.readOverrides();
    final raw = await ref.watch(fxServiceProvider).load(base: base);
    return FxState(snapshot: raw.withOverrides(overrides), overrides: overrides);
  }

  Future<void> refresh() async {
    final previous = state.valueOrNull;
    state = const AsyncLoading();
    try {
      final base = ref.read(defaultCurrencyProvider).code;
      final overrides = previous?.overrides ?? await FxStore.readOverrides();
      final raw = await ref
          .read(fxServiceProvider)
          .load(base: base, forceRefresh: true);
      state = AsyncData(
        FxState(snapshot: raw.withOverrides(overrides), overrides: overrides),
      );
    } catch (error, stack) {
      state = previous == null
          ? AsyncError(error, stack)
          : AsyncData(previous);
    }
  }

  Future<void> setOverride({
    required String from,
    required String to,
    required double rate,
  }) async {
    if (rate <= 0) return;
    final current = state.valueOrNull;
    final updates = <String, double>{
      ...(current?.overrides ?? const <String, double>{}),
      FxSnapshot.pairKey(from, to): rate,
    };
    await FxStore.writeOverrides(updates);
    final base = ref.read(defaultCurrencyProvider).code;
    if (current == null) {
      state = AsyncData(FxState(
        snapshot: FxSnapshot(
          base: base,
          rates: const <String, double>{},
          fetchedAt: DateTime.now(),
        ).withOverrides(updates),
        overrides: updates,
      ));
      return;
    }
    state = AsyncData(
      FxState(
        snapshot: current.snapshot.withOverrides(updates),
        overrides: updates,
      ),
    );
  }

  Future<void> removeOverride(String key) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updates = <String, double>{...current.overrides}..remove(key);
    await FxStore.writeOverrides(updates);
    state = AsyncData(
      FxState(
        snapshot: current.snapshot.withOverrides(updates),
        overrides: updates,
      ),
    );
  }
}

final exchangeRatesProvider =
    AsyncNotifierProvider<ExchangeRatesController, FxState>(
  ExchangeRatesController.new,
);

/// Convenience snapshot for synchronous widgets (null while loading).
final fxSnapshotProvider = Provider<FxSnapshot?>(
  (ref) => ref.watch(exchangeRatesProvider).valueOrNull?.snapshot,
);
