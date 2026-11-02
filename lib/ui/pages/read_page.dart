import 'package:flutter/material.dart';

import 'package:chameleon_ultra_next/ui/theme/app_theme.dart';

/// Placeholder for the redesigned read-card screen.
///
/// The previous implementation lived in a 1.5k-line `read_card.dart` widget that
/// mixed the scan flow, the card model and the UI. The models now live in
/// `core/models/card_info.dart`; this page is where the new scan UI goes.
class ReadPage extends StatelessWidget {
  const ReadPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Read card')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.sensors,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Scanning UI is being rebuilt', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'The scan and slot logic is already available through '
                  'ChameleonCommunicator, which is exposed by the shared '
                  'application state. Only the presentation layer is missing, '
                  'so this screen is intentionally empty for now.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
