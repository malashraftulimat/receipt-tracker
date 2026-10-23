import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/pay_cycle_provider.dart';
import '../../core/theme/app_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/budget_gradient_bar.dart';
import '../../core/widgets/language_switcher.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';
import '../../domain/models/monthly_budget.dart';
import '../../domain/models/pay_cycle.dart';
import '../../core/localization/localization.dart';

/// Income / savings goal / fixed expenses for a month + live pacing.
class BudgetPage extends ConsumerStatefulWidget {
  const BudgetPage({super.key});

  @override
  ConsumerState<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends ConsumerState<BudgetPage> {
  final _formKey = GlobalKey<FormState>();
  final _salary = TextEditingController();
  final _savings = TextEditingController();
  final _fixed = TextEditingController();

  late DateTime _month;
  String? _budgetId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _salary.dispose();
    _savings.dispose();
    _fixed.dispose();
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
      if (!mounted) return;
      final config = ref.read(payCycleProvider);
      setState(() {
        _budgetId = budget?.id;
        _salary.text = _formatInput(_incomePerCycle(budget, config));
        _savings.text = _formatInput(budget?.savingsGoal);
        _fixed.text = _formatInput(budget?.fixedExpenses);
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

  /// Income the user typed for the active cycle.
  ///
  /// The stored value is reused when the plan was saved with the same cycle,
  /// otherwise the monthly income is converted back (e.g. after switching from
  /// monthly to weekly pay in Settings).
  int _incomePerCycle(MonthlyBudget? budget, PayCycleConfig config) {
    if (budget == null) return 0;
    final stored = budget.incomePerCycle;
    if (stored != null && budget.payCycle == config.cycle) return stored;
    return config.perCycleEquivalent(budget.salary, _month);
  }

  String _formatInput(int? value) =>
      (value == null || value == 0) ? '' : formatAmountDigits(value);

  String _incomeLabel(PayCycle cycle) => switch (cycle) {
        PayCycle.daily => 'daily_income_net',
        PayCycle.weekly => 'weekly_income_net',
        PayCycle.monthly => 'monthly_income_net',
      };

  String _incomeHint(PayCycle cycle) => switch (cycle) {
        PayCycle.daily => 'e_g_10_000',
        PayCycle.weekly => 'e_g_50_000',
        PayCycle.monthly => 'e_g_250_000',
      };

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
      final config = ref.read(payCycleProvider);
      final incomePerCycle = parseYenInput(_salary.text) ?? 0;
      final budget = MonthlyBudget(
        id: _budgetId,
        month: _month,
        // Monthly figure used by analytics; the typed amount is kept verbatim
        // so daily / weekly plans survive round-trips without rounding drift.
        salary: config.monthlyEquivalent(incomePerCycle, _month),
        savingsGoal: parseYenInput(_savings.text) ?? 0,
        fixedExpenses: parseYenInput(_fixed.text) ?? 0,
        payCycle: config.cycle,
        incomePerCycle: incomePerCycle,
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
    final config = ref.watch(payCycleProvider);

    // Keep the form in sync when the salary cycle changes in Settings.
    ref.listen<PayCycleConfig>(payCycleProvider, (previous, next) {
      if (previous?.cycle != next.cycle) _load();
    });

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
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.payments_outlined,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: AppText(
                          'you_can_change_the_salary_cycle_in_settings',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _MoneyField(
                    controller: _salary,
                    label: _incomeLabel(config.cycle),
                    hint: _incomeHint(config.cycle),
                    icon: Icons.work_outline,
                  ),
                  if (!config.isMonthly) ...<Widget>[
                    const SizedBox(height: 6),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _salary,
                      builder: (context, value, _) {
                        final perCycle = parseYenInput(value.text) ?? 0;
                        final monthly =
                            config.monthlyEquivalent(perCycle, _month);
                        return AppText(
                          '月換算: ${formatYen(monthly)}'
                          '（この月の日数で計算）',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  _MoneyField(
                    controller: _savings,
                    label: 'savings_goal',
                    hint: 'e_g_30_000',
                    icon: Icons.savings_outlined,
                  ),
                  const SizedBox(height: 12),
                  _MoneyField(
                    controller: _fixed,
                    label: 'fixed_expenses_rent_utilities_subscriptions',
                    hint: 'e_g_80_000',
                    icon: Icons.home_outlined,
                  ),
                  const SizedBox(height: 6),
                  AppText(
                    'enter_the_savings_goal_and_fixed_costs_as_mo',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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
            data: (summary) => _SummaryCard(summary: summary),
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
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
      ],
      decoration: InputDecoration(
        labelText: context.tr(label),
        hintText: context.tr(hint),
        prefixText: '¥ ',
        prefixIcon: Icon(icon),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({this.summary, this.error});

  final BudgetSummary? summary;
  final String? error;

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
            formatYen(data.periodRemaining.abs()),
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
              '対象期間: '
              '${formatRangeJa(data.periodStart!, addDays(data.periodEnd!, -1))}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          BudgetGradientBar(value: data.periodProgress, height: 11),
          const SizedBox(height: 6),
          AppText(
            '支出 ${formatYen(data.cycleSpent)} / 自由枠 '
            '${formatYen(data.cycleBudget)} '
            '(${(data.periodProgress * 100).clamp(0, 999).toStringAsFixed(0)}%)',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _Metric(
                  label: 'per_day',
                  value: formatYen(data.dailyAllowance),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'today_s_spending',
                  value: formatYen(data.todaySpent),
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
            _pacingMessage(data),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  String _pacingMessage(BudgetSummary data) {
    if (data.periodStatus == BudgetStatus.overBudget) {
      return '予算を超えています。残り日数は ${data.periodDaysRemaining} 日です。';
    }
    if (data.periodVelocityDelta > 0) {
      return '計画より ${formatYen(data.periodVelocityDelta)} 多く使っています。'
          '残り ${data.periodDaysRemaining} 日、'
          '1日 ${formatYen(data.dailyAllowance)} が目安です。';
    }
    return '計画より ${formatYen(-data.periodVelocityDelta)} 節約できています。'
        'このペースなら貯蓄目標 ${formatYen(data.budget?.savingsGoal ?? 0)} に届きます。';
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
