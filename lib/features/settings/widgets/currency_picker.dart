import 'package:flutter/material.dart';

import '../../../core/localization/currencies.dart';
import '../../../core/localization/localization.dart';

/// Opens the searchable currency picker. Returns the chosen currency or null.
Future<Currency?> showCurrencyPicker(
  BuildContext context, {
  required Currency selected,
}) {
  return showModalBottomSheet<Currency>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _CurrencyPickerSheet(selected: selected),
  );
}

class _CurrencyPickerSheet extends StatefulWidget {
  const _CurrencyPickerSheet({required this.selected});

  final Currency selected;

  @override
  State<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<_CurrencyPickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final language = context.l10n.language;
    final height = MediaQuery.sizeOf(context).height * 0.88;
    final results = _query.trim().isEmpty
        ? const <Currency>[]
        : kCurrencies.where((currency) => currency.matches(_query)).toList();

    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: height,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: AppText(
              'currency.picker_title',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              autofocus: false,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: context.tr('currency.search_hint'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.tr('clear'),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: results.isEmpty && _query.trim().isNotEmpty
                ? Center(
                    child: AppText(
                      'currency.no_results',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: _buildList(context, language, results),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildList(
    BuildContext context,
    AppLanguage language,
    List<Currency> results,
  ) {
    final widgets = <Widget>[];
    if (results.isNotEmpty) {
      widgets.add(_sectionHeader(context, 'currency.all'));
      for (final currency in results) {
        widgets.add(_row(context, language, currency));
      }
      return widgets;
    }

    final common = commonCurrencies();
    widgets.add(_sectionHeader(context, 'currency.common'));
    for (final currency in common) {
      widgets.add(_row(context, language, currency));
    }
    widgets.add(const Divider(height: 12));
    widgets.add(_sectionHeader(context, 'currency.all'));
    for (final currency in kCurrencies) {
      widgets.add(_row(context, language, currency));
    }
    return widgets;
  }

  Widget _sectionHeader(BuildContext context, String key) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: AppText(
        key,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _row(BuildContext context, AppLanguage language, Currency currency) {
    final theme = Theme.of(context);
    final selected = currency.code == widget.selected.code;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: SizedBox(
        width: 46,
        child: Text(
          currency.symbol,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(
        currency.name(language),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${currency.code} · ${currency.symbol}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, size: 20)
          : null,
      selected: selected,
      onTap: () => Navigator.pop(context, currency),
    );
  }
}
