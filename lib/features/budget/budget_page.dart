import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/currencies.dart';
import '../../core/localization/localization.dart';
import '../../core/settings/currency_provider.dart';
import '../../core/theme/app_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/budget_gradient_bar.dart';
import '../../core/widgets/language_switcher.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';
import '../../domain/models/category.dart';
import '../../domain/models/income_source.dart';
import '../../domain/models/monthly_budget.dart';
import '../../domain/models/pay_cycle.dart';
import '../../domain/models/wallet.dart';

/// Income / savings goal / fixed expenses for a month + live pacing.
class BudgetPage extends ConsumerStatefulWidget {
  const BudgetPage({super.key});

  @override
  ConsumerState<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends ConsumerState<BudgetPage> {
  final _formKey = GlobalKey<FormState>();
  final _overall = TextEditingController();
  final _savings = TextEditingController();
  final _fixed = TextEditingController();
  final Map<String, TextEditingController> _categoryLimitControllers =
      <String, TextEditingController>{};

  late DateTime _month;
  String? _budgetId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// Legacy plan amounts, used only when the user has no income sources (for
  /// example after deleting every source).
  double _fallbackSalary = 0;
  PayCycle? _fallbackCycle;
  num? _fallbackIncomePerCycle;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _overall.dispose();
    _savings.dispose();
    _fixed.dispose();
    for (final controller in _categoryLimitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final budget =
          await ref.read(budgetRepositoryProvider).fetchMonth(_month);
      final categories = await ref.read(categoriesProvider.future);
      if (!mounted) return;
      final digits = ref.read(defaultCurrencyProvider).decimalDigits;
      for (final category in categories) {
        final controller = _categoryLimitControllers.putIfAbsent(
          category.id,
          () => TextEditingController(),
        );
        controller.text = _formatInput(
          budget?.categoryLimits[category.id],
          digits,
        );
      }
      setState(() {
        _budgetId = budget?.id;
        _fallbackSalary = (budget?.salary ?? 0).toDouble();
        _fallbackCycle = budget?.payCycle;
        _fallbackIncomePerCycle = budget?.incomePerCycle;
        _overall.text = _formatInput(budget?.overallLimit, digits);
        _savings.text = _formatInput(budget?.savingsGoal, digits);
        _fixed.text = _formatInput(budget?.fixedExpenses, digits);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _formatInput(num? value, int decimalDigits) =>
      (value == null || value == 0)
          ? ''
          : formatAmountDigits(value, decimalDigits: decimalDigits);

  /// Active source total for [month], or the legacy plan salary.
  double _monthlyIncome(List<IncomeSource> sources) {
    if (sources.isEmpty) return _fallbackSalary;
    return sources.where((source) => source.active).fold<double>(0,
        (sum, source) {
      return sum + source.monthlyEquivalent(_month).toDouble();
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    _load();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final sources = ref.read(incomeSourcesProvider).valueOrNull ??
          const <IncomeSource>[];
      final defining = budgetDefiningSource(sources);
      final config = ref.read(budgetPayCycleProvider);
      final salary = _monthlyIncome(sources);
      final budget = MonthlyBudget(
        id: _budgetId,
        month: _month,
        // Income comes from the source list; the stored salary/payCycle keeps
        // the plan readable by older builds and is a fallback when the list is
        // empty.
        salary: salary,
        savingsGoal: parseAmountInput(_savings.text) ?? 0,
        fixedExpenses: parseAmountInput(_fixed.text) ?? 0,
        payCycle: defining?.cycle ?? _fallbackCycle ?? config.cycle,
        incomePerCycle: defining?.amountPerCycle ?? _fallbackIncomePerCycle,
        overallLimit: parseAmountInput(_overall.text) ?? 0,
        categoryLimits: <String, double>{
          for (final category in (ref
                  .read(categoriesProvider)
                  .valueOrNull ??
              const <ExpenseCategory>[]))
            if ((parseAmountInput(
                        _categoryLimitControllers[category.id]?.text ?? '',
                      ) ??
                    0) >
                0)
              category.id: parseAmountInput(
                _categoryLimitControllers[category.id]?.text ?? '',
              )!,
        },
      );
      final saved = await ref.read(budgetRepositoryProvider).save(budget);
      if (!mounted) return;
      setState(() {
        _budgetId = saved.id;
        _saving = false;
      });
      ref.invalidate(budgetProvider(_month));
      ref.invalidate(budgetSummaryProvider(_month));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('budget_saved')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存に失敗しました: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summaryAsync = ref.watch(budgetSummaryProvider(_month));
    final config = ref.watch(budgetPayCycleProvider);
    final currency = ref.watch(defaultCurrencyProvider);
    final sources =
        ref.watch(incomeSourcesProvider).valueOrNull ?? const <IncomeSource>[];
    final defining = budgetDefiningSource(sources);
    final monthlyIncome = _monthlyIncome(sources);
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <ExpenseCategory>[];

    return Scaffold(
      appBar: AppBar(
        title: const AppText('budget_and_savings'),
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          context.pagePadding,
          8,
          context.pagePadding,
          40,
        ),
        children: <Widget>[
          _MonthSelector(
            month: _month,
            onPrevious: () => _changeMonth(-1),
            onNext: () => _changeMonth(1),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(context),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AppText(
                    config.isMonthly ? 'monthly_plan' : 'pay_plan',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  AppText(
                    'income_sources_manage_in_settings',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: AppText(
                                'income_sources',
                                style: theme.textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.push('/settings'),
                              child: const AppText('manage'),
                            ),
                          ],
                        ),
                        AppText(
                          'income.monthly_equivalent_total',
                          params: <String, Object?>{
                            'amount': formatMoney(
                              monthlyIncome,
                              currency: currency.code,
                            ),
                          },
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (defining != null) ...<Widget>[
                          const SizedBox(height: 4),
                          AppText(
                            'income.budget_source',
                            params: <String, Object?>{
                              'name': defining.name,
                              'cycle': context.tr(defining.cycle.name),
                              'amount': formatMoney(
                                defining.amountPerCycle,
                                currency: defining.currency,
                              ),
                            },
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (sources.isEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          AppText(
                            'no_income_sources',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MoneyField(
                    controller: _overall,
                    label: 'overall_budget_limit',
                    hint: 'e_g_200_000',
                    icon: Icons.stacked_line_chart_outlined,
                    symbol: currency.symbol,
                    decimalDigits: currency.decimalDigits,
                  ),
                  const SizedBox(height: 6),
                  AppText(
                    'overall_budget_limit_help',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MoneyField(
                    controller: _savings,
                    label: 'savings_goal',
                    hint: 'e_g_30_000',
                    icon: Icons.savings_outlined,
                    symbol: currency.symbol,
                    decimalDigits: currency.decimalDigits,
                  ),
                  const SizedBox(height: 12),
                  _MoneyField(
                    controller: _fixed,
                    label: 'fixed_expenses_rent_utilities_subscriptions',
                    hint: 'e_g_80_000',
                    icon: Icons.home_outlined,
                    symbol: currency.symbol,
                    decimalDigits: currency.decimalDigits,
                  ),
                  const SizedBox(height: 6),
                  AppText(
                    'enter_the_savings_goal_and_fixed_costs_as_mo',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (categories.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    AppText(
                      'budget.category_limits',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    AppText(
                      'budget.category_limits_help',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final category in categories)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              category.iconData,
                              size: 18,
                              color: category.colorValue,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: AppText(category.name)),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 140,
                              child: TextFormField(
                                controller: _categoryLimitControllers
                                    .putIfAbsent(
                                  category.id,
                                  () => TextEditingController(),
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: '0',
                                  prefixText: '${currency.symbol} ',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    AppText(
                      _error!,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: (_saving || _loading) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const AppText('save_plan'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          summaryAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => _SummaryCard(
              error: error.toString(),
            ),
            data: (summary) => _SummaryCard(
              summary: summary,
              currencyCode: currency.code,
            ),
          ),
          const SizedBox(height: 14),
          summaryAsync.maybeWhen(
            data: (summary) => _CategoryLimitsCard(
              summary: summary,
              categories: categories,
              currencyCode: currency.code,
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 14),
          _WalletSpendingCard(
            month: _month,
            currencyCode: currency.code,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: AppText(
              'budget.help',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryLimitsCard extends StatelessWidget {
  const _CategoryLimitsCard({
    required this.summary,
    required this.categories,
    required this.currencyCode,
  });

  final BudgetSummary summary;
  final List<ExpenseCategory> categories;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final limits = summary.budget?.categoryLimits ?? const <String, double>{};
    if (limits.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppPalette.card(context, accent: AppPalette.violet, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppText(
            'budget.category_limits',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (final category in categories)
            if ((limits[category.id] ?? 0) > 0)
              _CategoryLimitRow(
                category: category,
                spent: summary.categorySpent[category.id] ?? 0,
                limit: limits[category.id]!,
                currencyCode: currencyCode,
              ),
        ],
      ),
    );
  }
}

class _CategoryLimitRow extends StatelessWidget {
  const _CategoryLimitRow({
    required this.category,
    required this.spent,
    required this.limit,
    required this.currencyCode,
  });

  final ExpenseCategory category;
  final double spent;
  final double limit;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = limitStatus(spent, limit);
    final color = switch (status) {
      LimitStatus.none => theme.colorScheme.outline,
      LimitStatus.ok => AppPalette.emerald,
      LimitStatus.warning => AppPalette.amber,
      LimitStatus.over => AppPalette.danger,
    };
    final percent = limit <= 0 ? 0 : (spent / limit * 100);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(category.iconData, size: 16, color: category.colorValue),
              const SizedBox(width: 6),
              Expanded(child: AppText(category.name)),
              if (status == LimitStatus.warning || status == LimitStatus.over)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: AppPalette.tintedPill(color, radius: 8),
                  child: AppText(
                    status == LimitStatus.over
                        ? 'budget.limit_over'
                        : 'budget.limit_warning',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: (spent / limit).clamp(0.0, 1.0),
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            backgroundColor:
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            color: color,
          ),
          const SizedBox(height: 4),
          AppText(
            'budget.category_limit_progress',
            params: <String, Object?>{
              'spent': formatMoney(spent, currency: currencyCode),
              'limit': formatMoney(limit, currency: currencyCode),
              'percent': percent.clamp(0, 999).toStringAsFixed(0),
            },
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletSpendingCard extends ConsumerWidget {
  const _WalletSpendingCard({
    required this.month,
    required this.currencyCode,
  });

  final DateTime month;
  final String currencyCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spending = ref.watch(walletSpendingProvider(month)).valueOrNull;
    final wallets = ref.watch(walletsProvider).valueOrNull ?? const <Wallet>[];
    if (spending == null) return const SizedBox.shrink();
    final rows = <(Wallet, double)>[];
    for (final wallet in wallets) {
      final amount = spending.byWallet[wallet.id] ?? 0;
      if (amount > 0) rows.add((wallet, amount));
    }
    if (rows.isEmpty && spending.unassigned <= 0) {
      return const SizedBox.shrink();
    }
    rows.sort((a, b) => b.$2.compareTo(a.$2));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppPalette.card(context, accent: AppPalette.cyan, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppText(
            'budget.spending_by_wallet',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 16,
                    color: Color(row.$1.colorValue),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppText(
                      row.$1.name,
                      translate: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AppText(
                    formatMoney(row.$2, currency: row.$1.currency),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          if (spending.unassigned > 0) ...<Widget>[
            const SizedBox(height: 4),
            AppText(
              'budget.unassigned_spending',
              params: <String, Object?>{
                'amount': formatMoney(
                  spending.unassigned,
                  currency: currencyCode,
                ),
              },
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: context.tr('previous_month'),
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: AppText(
            formatMonthJa(month),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: context.tr('next_month'),
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.symbol,
    required this.decimalDigits,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String symbol;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(
        decimal: decimalDigits > 0,
      ),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: context.tr(label),
        hintText: context.tr(hint),
        prefixText: '$symbol ',
        prefixIcon: Icon(icon),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    this.summary,
    this.error,
    this.currencyCode = kFallbackCurrencyCode,
  });

  final BudgetSummary? summary;
  final String? error;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(context),
        child: AppText('集計を読み込めませんでした\n$error'),
      );
    }

    final data = summary;
    if (data == null) {
      return const SizedBox.shrink();
    }

    if (!data.configured) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(context),
        child: AppText(
          'no_plan_for_this_month_enter_your_income_in',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final statusColor = switch (data.periodStatus) {
      BudgetStatus.onTrack => AppPalette.emerald,
      BudgetStatus.warning => AppPalette.amber,
      BudgetStatus.overBudget => AppPalette.danger,
      BudgetStatus.unset => AppPalette.violet,
    };
    final activePeriod = data.periodStart != null;
    final monthStart = DateTime(data.month.year, data.month.month);
    final monthEnd = DateTime(data.month.year, data.month.month + 1);
    final showPeriodRange = data.periodStart != null &&
        data.periodEnd != null &&
        !(data.periodStart!.isAtSameMomentAs(monthStart) &&
            data.periodEnd!.isAtSameMomentAs(monthEnd));
    final periodLabel = !activePeriod
        ? 'this_month_s_status'
        : switch (data.payCycle) {
            PayCycle.daily => 'today_s_status',
            PayCycle.weekly => 'this_week_s_status',
            PayCycle.monthly => 'this_month_s_status',
          };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppText(
                periodLabel,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: AppPalette.tintedPill(
                  statusColor,
                  radius: 8,
                ),
                child: AppText(
                  data.periodStatusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppText(
            formatMoney(data.periodRemaining.abs(), currency: currencyCode),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: data.periodRemaining < 0
                  ? AppPalette.danger
                  : AppPalette.emerald,
            ),
          ),
          AppText(
            data.periodRemaining < 0
                ? 'over_budget'
                : (!activePeriod
                    ? 'remaining_budget_this_month'
                    : data.periodRemainingLabel),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (showPeriodRange) ...<Widget>[
            const SizedBox(height: 2),
            AppText(
              'budget.period_range',
              params: <String, Object?>{
                'range': formatRangeJa(
                  data.periodStart!,
                  addDays(data.periodEnd!, -1),
                ),
              },
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          BudgetGradientBar(value: data.periodProgress, height: 11),
          const SizedBox(height: 6),
          AppText(
            'budget.spent_of_allowance',
            params: <String, Object?>{
              'spent': formatMoney(data.cycleSpent, currency: currencyCode),
              'allowance': formatMoney(
                data.cycleBudget,
                currency: currencyCode,
              ),
              'percent':
                  (data.periodProgress * 100).clamp(0, 999).toStringAsFixed(0),
            },
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _Metric(
                  label: 'per_day',
                  value: formatMoney(data.dailyAllowance, currency: currencyCode),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'today_s_spending',
                  value: formatMoney(data.todaySpent, currency: currencyCode),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'savings_pace',
                  value: '${(data.savingsProgress * 100).round()}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppText(
            'income.period_and_monthly',
            params: <String, Object?>{
              'period': formatMoney(
                data.periodIncome,
                currency: currencyCode,
              ),
              'monthly': formatMoney(
                data.monthlyIncome,
                currency: currencyCode,
              ),
            },
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          AppText(
            _pacingMessage(data),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          if (data.otherCurrencyCount > 0) ...<Widget>[
            const SizedBox(height: 8),
            AppText(
              'currency.other_note',
              count: data.otherCurrencyCount,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _pacingMessage(BudgetSummary data) {
    if (data.periodStatus == BudgetStatus.overBudget) {
      return '予算を超えています。残り日数は ${data.periodDaysRemaining} 日です。';
    }
    if (data.periodVelocityDelta > 0) {
      return '計画より ${formatMoney(data.periodVelocityDelta, currency: currencyCode)} 多く使っています。'
          '残り ${data.periodDaysRemaining} 日、'
          '1日 ${formatMoney(data.dailyAllowance, currency: currencyCode)} が目安です。';
    }
    return '計画より ${formatMoney(-data.periodVelocityDelta, currency: currencyCode)} 節約できています。'
        'このペースなら貯蓄目標 ${formatMoney(data.budget?.savingsGoal ?? 0, currency: currencyCode)} に届きます。';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppText(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        AppText(
          value,
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

BoxDecoration _cardDecoration(BuildContext context) => AppPalette.card(
      context,
      accent: AppPalette.violet,
      radius: 18,
    );
