import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chameleon_ultra_next/helpers/flash.dart';

void main() {
  test('firmware package passes integrity validation', () async {
    final file = File('../artifacts/firmware/ultra/ultra-dfu-app.zip');
    if (!await file.exists()) {
      return;
    }
    final (dat, bin) = await unpackFirmware(await file.readAsBytes());
    expect(dat, isNotEmpty);
    expect(bin, isNotEmpty);
    expect(() => validateFiles(dat, bin), returnsNormally);
  });
}
