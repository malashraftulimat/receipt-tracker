import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../core/widgets/press_scale.dart';
import 'widgets/analytics_panel.dart';
import 'widgets/budget_card.dart';
import 'widgets/due_reminders_card.dart';
import 'widgets/filter_bar.dart';
import 'widgets/receipt_collection.dart';
import '../../core/localization/localization.dart';

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
        title: const AppText('receipt_tracker'),
        actions: headerActions(
          context,
          showLanguageLabel: expanded,
          actions: <Widget>[
            IconButton(
              tooltip: context.tr('add_payment'),
              onPressed: () => context.push('/payment/new'),
              icon: const Icon(Icons.add_card_outlined),
            ),
            if (!expanded)
              IconButton(
                tooltip: context.tr('analytics'),
                onPressed: () => _showAnalyticsSheet(context),
                icon: const Icon(Icons.insights_outlined),
              ),
          ],
        ),
      ),
      floatingActionButton: PressScale(
        child: FloatingActionButton.extended(
          onPressed: () => context.push('/scan'),
          backgroundColor: AppPalette.cyan,
          foregroundColor: AppPalette.backgroundDeep,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const AppText('scan'),
        ),
      ),
      body: SafeArea(
        child: expanded
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Expanded(child: _MainPane()),
                  Container(
                    width: 1,
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(
                    width: 372,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
                      child: AnalyticsPanel(),
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
