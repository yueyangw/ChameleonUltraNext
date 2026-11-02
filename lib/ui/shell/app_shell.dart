import 'package:flutter/material.dart';

import 'package:chameleon_ultra_next/ui/pages/settings_page.dart';
import 'package:chameleon_ultra_next/ui/pages/tools_page.dart';
import 'package:chameleon_ultra_next/ui/pages/wallet_page.dart';
import 'package:chameleon_ultra_next/ui/pages/workbench_page.dart';

/// Root navigation shell of the rewritten client.
///
/// Compact layouts use a bottom navigation bar; tablets and landscape
/// devices switch to a navigation rail without changing the page state.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const List<_ShellDestination> _destinations = <_ShellDestination>[
    _ShellDestination(
      label: '工作台',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    _ShellDestination(
      label: '卡包',
      icon: Icons.wallet_outlined,
      selectedIcon: Icons.wallet,
    ),
    _ShellDestination(
      label: '工具',
      icon: Icons.handyman_outlined,
      selectedIcon: Icons.handyman,
    ),
    _ShellDestination(
      label: '设置',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];

  Widget _pageFor(int index) {
    switch (index) {
      case 0:
        return const WorkbenchPage();
      case 1:
        return const WalletPage();
      case 2:
        return const ToolsPage();
      default:
        return const SettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    final body = IndexedStack(
      index: _index,
      children: <Widget>[
        for (var i = 0; i < _destinations.length; i++) _pageFor(i),
      ],
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: _index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (int value) =>
                  setState(() => _index = value),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Icon(Icons.memory_rounded),
              ),
              destinations: <NavigationRailDestination>[
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) => setState(() => _index = value),
        destinations: <NavigationDestination>[
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
