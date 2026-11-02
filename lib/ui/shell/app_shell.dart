import 'package:flutter/material.dart';

import 'package:chameleon_ultra_next/ui/pages/device_page.dart';
import 'package:chameleon_ultra_next/ui/pages/read_page.dart';
import 'package:chameleon_ultra_next/ui/pages/settings_page.dart';
import 'package:chameleon_ultra_next/ui/theme/app_theme.dart';

/// Root navigation shell of the rewritten client.
///
/// The old client used a single 370-line `MainPage` widget with a hardcoded
/// sidebar. Pages are now independent widgets so each screen can be redesigned
/// without touching the others.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const List<_ShellDestination> _destinations = <_ShellDestination>[
    _ShellDestination(
      label: 'Device',
      icon: Icons.usb_outlined,
      selectedIcon: Icons.usb,
    ),
    _ShellDestination(
      label: 'Read',
      icon: Icons.sensors_outlined,
      selectedIcon: Icons.sensors,
    ),
    _ShellDestination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];

  Widget _pageFor(int index) {
    switch (index) {
      case 0:
        return const DevicePage();
      case 1:
        return const ReadPage();
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
              onDestinationSelected: (int value) => setState(() => _index = value),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
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
