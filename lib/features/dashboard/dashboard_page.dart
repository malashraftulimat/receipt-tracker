import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/responsive.dart';
import 'widgets/analytics_panel.dart';
import 'widgets/budget_card.dart';
import 'widgets/due_reminders_card.dart';
import 'widgets/filter_bar.dart';
import 'widgets/receipt_collection.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  void _showAnalyticsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: const AnalyticsPanel(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expanded = context.isExpanded;

    return Scaffold(
      appBar: AppBar(
        title: const Text('レシート帳'),
        actions: <Widget>[
          if (!expanded)
            IconButton(
              tooltip: '集計',
              onPressed: () => _showAnalyticsSheet(context),
              icon: const Icon(Icons.insights_outlined),
            ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/scan'),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('スキャン'),
      ),
      body: SafeArea(
        child: expanded
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Expanded(child: _MainPane()),
                  Container(
                    width: 1,
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                  SizedBox(
                    width: 372,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      child: const AnalyticsPanel(),
                    ),
                  ),
                ],
              )
            : const _MainPane(),
      ),
    );
  }
}

class _MainPane extends StatelessWidget {
  const _MainPane();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        BudgetCard(),
        DueRemindersCard(),
        FilterBar(),
        Expanded(child: ReceiptCollection()),
      ],
    );
  }
}
