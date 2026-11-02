import 'package:flutter/material.dart';

import 'package:chameleon_ultra_next/app/app.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sharedPreferencesProvider = SharedPreferencesProvider();
  await sharedPreferencesProvider.load();

  runApp(ChameleonApp(sharedPreferencesProvider: sharedPreferencesProvider));
}
