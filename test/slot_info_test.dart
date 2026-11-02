import 'package:flutter_test/flutter_test.dart';

import 'package:chameleon_ultra_next/core/models/slot_info.dart';

void main() {
  group('PollingConfiguration', () {
    test('round trips through the wire format', () {
      final config = PollingConfiguration(
        enabled: true,
        slotMask: 0xA5A5,
        idleDwellMs: 350,
        activeDwellMs: 1500,
        cooldownMs: 250,
        adaptive: true,
        jitterPercent: 15,
        order: 1,
        keepAwake: false,
      );

      final decoded = PollingConfiguration.fromBytes(config.toBytes());

      expect(decoded.enabled, isTrue);
      expect(decoded.slotMask, 0xA5A5);
      expect(decoded.idleDwellMs, 350);
      expect(decoded.activeDwellMs, 1500);
      expect(decoded.cooldownMs, 250);
      expect(decoded.adaptive, isTrue);
      expect(decoded.jitterPercent, 15);
      expect(decoded.order, 1);
      expect(decoded.keepAwake, isFalse);
    });

    test('has safe defaults', () {
      final config = PollingConfiguration();
      expect(config.enabled, isFalse);
      expect(config.idleDwellMs, 500);
      expect(config.activeDwellMs, 2000);
    });
  });
}