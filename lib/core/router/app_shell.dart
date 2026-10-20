import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/responsive.dart';
import '../localization/localization.dart';

/// Responsive chrome: NavigationRail on desktop, NavigationBar on mobile.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  static const List<String> _routes = <String>[
    '/dashboard',
    '/categories',
    '/settings',
  ];

  int get _index {
    if (location.startsWith('/categories')) return 1;
    if (location.startsWith('/settings')) return 2;
    return 0;
  }

  void _go(BuildContext context, int index) => context.go(_routes[index]);

  @override
  Widget build(BuildContext context) {
    if (context.isExpanded) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (index) => _go(context, index),
              leading: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: FloatingActionButton(
                  heroTag: 'scan-rail',
                  tooltip: context.tr('レシートをスキャン'),
                  onPressed: () => context.push('/scan'),
                  child: const Icon(Icons.document_scanner_outlined),
                ),
              ),
              destinations: const <NavigationRailDestination>[
                NavigationRailDestination(
                  icon: Icon(Icons.space_dashboard_outlined),
                  selectedIcon: Icon(Icons.space_dashboard),
                  label: AppText('ホーム'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.sell_outlined),
                  selectedIcon: Icon(Icons.sell),
                  label: AppText('カテゴリ'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: AppText('設定'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => _go(context, index),
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.space_dashboard_outlined),
            selectedIcon: const Icon(Icons.space_dashboard),
            label: context.tr('ホーム'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.sell_outlined),
            selectedIcon: const Icon(Icons.sell),
            label: context.tr('カテゴリ'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: context.tr('設定'),
          ),
        ],
      ),
    );
  }
}
