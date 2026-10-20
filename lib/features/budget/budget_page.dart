import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';
import '../../domain/models/monthly_budget.dart';
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
      setState(() {
        _budgetId = budget?.id;
        _salary.text = _formatInput(budget?.salary);
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

  String _formatInput(int? value) =>
      (value == null || value == 0) ? '' : formatAmountDigits(value);

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
      final budget = MonthlyBudget(
        id: _budgetId,
        month: _month,
        salary: parseYenInput(_salary.text) ?? 0,
        savingsGoal: parseYenInput(_savings.text) ?? 0,
        fixedExpenses: parseYenInput(_fixed.text) ?? 0,
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
        const SnackBar(content: AppText('予算を保存しました')),
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

    return Scaffold(
      appBar: AppBar(title: const AppText('予算と貯蓄')),
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
            decoration: _cardDecoration(theme),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AppText(
                    '毎月のプラン',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  _MoneyField(
                    controller: _salary,
                    label: '月収（手取り）',
                    hint: '例: 250,000',
                    icon: Icons.work_outline,
                  ),
                  const SizedBox(height: 12),
                  _MoneyField(
                    controller: _savings,
                    label: '貯蓄目標',
                    hint: '例: 30,000',
                    icon: Icons.savings_outlined,
                  ),
                  const SizedBox(height: 12),
                  _MoneyField(
                    controller: _fixed,
                    label: '固定費（家賃・光熱費・サブスク）',
                    hint: '例: 80,000',
                    icon: Icons.home_outlined,
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
                    label: const AppText('プランを保存'),
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
              '自由に使える金額 = 月収 − 貯蓄目標 − 固定費。\n'
              'レシートを登録すると、その月の残り予算から自動で差し引かれます。\n'
              '「1日あたり」は残り予算 ÷ 残り日数です。',
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
          tooltip: context.tr('前の月'),
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
          tooltip: context.tr('次の月'),
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
        labelText: label,
        hintText: hint,
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
        decoration: _cardDecoration(theme),
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
        decoration: _cardDecoration(theme),
        child: AppText(
          'この月のプランは未設定です。上のフォームに月収を入力してください。',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final statusColor = switch (data.status) {
      BudgetStatus.onTrack => const Color(0xFF2E7D32),
      BudgetStatus.warning => const Color(0xFFEF6C00),
      BudgetStatus.overBudget => theme.colorScheme.error,
      BudgetStatus.unset => theme.colorScheme.outline,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppText(
                '今月の状況',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AppText(
                  data.statusLabel,
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
            formatYen(data.remaining.abs()),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: data.remaining < 0 ? theme.colorScheme.error : null,
            ),
          ),
          AppText(
            data.remaining < 0 ? '予算オーバー額' : '今月の残り予算',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: data.progress.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 6),
          AppText(
            '支出 ${formatYen(data.spent)} / 自由枠 ${formatYen(data.disposable)} '
            '(${(data.progress * 100).clamp(0, 999).toStringAsFixed(0)}%)',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _Metric(
                  label: '1日あたり',
                  value: formatYen(data.dailyAllowance),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: '今日の支出',
                  value: formatYen(data.todaySpent),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: '貯蓄ペース',
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
    if (data.status == BudgetStatus.overBudget) {
      return '予算を超えています。残り日数は ${data.daysRemaining} 日です。';
    }
    if (data.velocityDelta > 0) {
      return '計画より ${formatYen(data.velocityDelta)} 多く使っています。'
          '残り ${data.daysRemaining} 日、1日 ${formatYen(data.dailyAllowance)} が目安です。';
    }
    return '計画より ${formatYen(-data.velocityDelta)} 節約できています。'
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
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

BoxDecoration _cardDecoration(ThemeData theme) => BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
      ),
    );
