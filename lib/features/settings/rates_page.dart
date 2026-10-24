import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/currencies.dart';
import '../../core/localization/localization.dart';
import '../../core/settings/currency_provider.dart';
import '../../core/settings/exchange_rates_provider.dart';
import '../../core/theme/app_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../domain/models/exchange_rates.dart';
import 'widgets/currency_picker.dart';

class RatesPage extends ConsumerWidget {
  const RatesPage({super.key});

  Future<void> _addOverride(
    BuildContext context,
    WidgetRef ref,
    FxState state,
  ) async {
    final base = ref.read(defaultCurrencyProvider);
    final defaultFrom = currencyByCode(base.code) ?? kFallbackCurrency;
    final defaultTo = defaultFrom.code == 'USD'
        ? currencyByCode('EUR') ?? kFallbackCurrency
        : currencyByCode('USD') ?? kFallbackCurrency;
    final from = ValueNotifier<Currency>(defaultFrom);
    final to = ValueNotifier<Currency>(defaultTo);
    final rate = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('fx.add_override'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ValueListenableBuilder<Currency>(
                valueListenable: from,
                builder: (context, value, _) => OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showCurrencyPicker(
                      context,
                      selected: value,
                    );
                    if (picked != null) from.value = picked;
                  },
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: Text(
                    '${context.tr('fx.from')}: ${value.code}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<Currency>(
                valueListenable: to,
                builder: (context, value, _) => OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showCurrencyPicker(
                      context,
                      selected: value,
                    );
                    if (picked != null) to.value = picked;
                  },
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(
                    '${context.tr('fx.to')}: ${value.code}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: rate,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: context.tr('fx.rate'),
                  helperText: context.tr('fx.rate_help'),
                  prefixIcon: const Icon(Icons.calculate_outlined),
                ),
                validator: (value) {
                  final parsed = parseAmountInput(value ?? '');
                  if (parsed == null || parsed <= 0) {
                    return context.tr('enter_an_amount_greater_than_0');
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              if (from.value.code == to.value.code) return;
              Navigator.pop(context, true);
            },
            child: const AppText('save'),
          ),
        ],
      ),
    );

    if (result == true) {
      final parsed = parseAmountInput(rate.text);
      if (parsed != null && parsed > 0) {
        await ref.read(exchangeRatesProvider.notifier).setOverride(
              from: from.value.code,
              to: to.value.code,
              rate: parsed,
            );
      }
    }
    rate.dispose();
    from.dispose();
    to.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncState = ref.watch(exchangeRatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppText('exchange_rates'),
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
          actions: <Widget>[
            IconButton(
              tooltip: context.tr('fx.refresh'),
              onPressed: () => ref.read(exchangeRatesProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: asyncState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AppText('could_not_load_data: $error'),
            ),
          ),
          data: (state) {
            final snapshot = state.snapshot;
            final source = switch (snapshot.source) {
              FxSource.frankfurter => 'fx.source_frankfurter',
              FxSource.erApi => 'fx.source_er_api',
              FxSource.none => 'fx.source_none',
            };
            final asOf = '${formatDateJa(snapshot.fetchedAt)} '
                '${formatTimeJa(snapshot.fetchedAt)}';
            return ListView(
              padding: EdgeInsets.fromLTRB(
                context.pagePadding,
                8,
                context.pagePadding,
                40,
              ),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppPalette.card(
                    context,
                    accent: AppPalette.cyan,
                    radius: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      AppText(
                        'fx.rates_as_of',
                        params: <String, Object?>{'date': asOf},
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      AppText(
                        'fx.base_currency',
                        params: <String, Object?>{'code': snapshot.base},
                        style: theme.textTheme.bodySmall,
                      ),
                      AppText(
                        source,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (snapshot.fromCache)
                        const AppText(
                          'fx.cached_rates',
                          style: TextStyle(fontSize: 11),
                        ),
                      if (snapshot.stale)
                        AppText(
                          'fx.stale_rates',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      if (!snapshot.hasRates)
                        const AppText(
                          'fx.no_rates_offline',
                          style: TextStyle(fontSize: 11),
                        ),
                      const SizedBox(height: 6),
                      const AppText(
                        'fx.missing_rate_help',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppText(
                        'fx.manual_overrides',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _addOverride(context, ref, state),
                      icon: const Icon(Icons.add, size: 18),
                      label: const AppText('fx.add_override'),
                    ),
                  ],
                ),
                if (state.overrides.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: AppText('fx.no_overrides'),
                  )
                else
                  for (final entry in state.overrides.entries)
                    Card(
                      child: ListTile(
                        title: Text(entry.key),
                        subtitle: Text(
                          '1 ${entry.key.split('>').first} = '
                          '${entry.value} ${entry.key.split('>').last}',
                        ),
                        trailing: IconButton(
                          tooltip: context.tr('delete'),
                          onPressed: () => ref
                              .read(exchangeRatesProvider.notifier)
                              .removeOverride(entry.key),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                const SizedBox(height: 10),
                const AppText(
                  'fx.manual_override_wins',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
