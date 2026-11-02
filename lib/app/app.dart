import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/bridge/chameleon.dart';
import 'package:chameleon_ultra_next/connector/serial_abstract.dart';
import 'package:chameleon_ultra_next/connector/serial_android.dart';
import 'package:chameleon_ultra_next/connector/serial_ble.dart';
import 'package:chameleon_ultra_next/connector/serial_emulator.dart';
import 'package:chameleon_ultra_next/connector/serial_macos.dart';
import 'package:chameleon_ultra_next/connector/serial_native.dart';
import 'package:chameleon_ultra_next/generated/i18n/app_localizations.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';
import 'package:chameleon_ultra_next/ui/shell/app_shell.dart';
import 'package:chameleon_ultra_next/ui/theme/app_theme.dart';

/// Builds the transport layer used to talk to the device.
///
/// This mirrors the platform selection of the previous client so that the
/// device-facing behaviour does not change while the UI is being rebuilt.
AbstractSerial createConnector(SharedPreferencesProvider preferences) {
  final log = createLogger(preferences);

  if (preferences.isEmulatedChameleon()) {
    return EmulatorSerial(log: log);
  }

  if (Platform.isMacOS) {
    return MacOSSerial(log: log);
  }

  if (Platform.isAndroid) {
    return AndroidSerial(log: log);
  }

  if (Platform.isIOS) {
    return BLESerial(log: log);
  }

  return NativeSerial(log: log);
}

Logger createLogger(SharedPreferencesProvider preferences) {
  if (preferences.isDebugLogging() && preferences.isDebugMode()) {
    return Logger(
      output: SharedPreferencesLogger(preferences),
      printer: PrettyPrinter(noBoxingByDefault: true),
      filter: ChameleonLogFilter(),
    );
  }

  return Logger();
}

class ChameleonApp extends StatelessWidget {
  const ChameleonApp({super.key, required this.sharedPreferencesProvider});

  final SharedPreferencesProvider sharedPreferencesProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: sharedPreferencesProvider),
        ChangeNotifierProvider<ChameleonGUIState>(
          create: (_) {
            final state = ChameleonGUIState(sharedPreferencesProvider);
            state.log = createLogger(sharedPreferencesProvider);
            state.connector = createConnector(sharedPreferencesProvider);
            state.connector!.connectionStateCallback =
                state.onConnectorStateChanged;
            return state;
          },
        ),
      ],
      child: Consumer<SharedPreferencesProvider>(
        builder: (context, prefs, _) => MaterialApp(
          title: 'Chameleon Ultra Next',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(seedColor: prefs.getThemeColor()),
          darkTheme: AppTheme.dark(seedColor: prefs.getThemeColor()),
          themeMode: prefs.getTheme(),
          locale: prefs.getLocale(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AppShell(),
        ),
      ),
    );
  }
}
