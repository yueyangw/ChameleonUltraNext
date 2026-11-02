import 'dart:typed_data';

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

    test('uses the 24 byte layout with adaptive fields', () {
      final config = PollingConfiguration(
        txnHoldMs: 2500,
        hitBonusMs: 700,
        missShrinkPct: 30,
      );
      final bytes = config.toBytes();
      expect(bytes.length, 24);
      expect(bytes[0], 3);
      final decoded = PollingConfiguration.fromBytes(bytes);
      expect(decoded.supportsAdaptive, isTrue);
      expect(decoded.txnHoldMs, 2500);
      expect(decoded.hitBonusMs, 700);
      expect(decoded.missShrinkPct, 30);
    });

    test('keeps the padded 16 byte layout for the previous firmware', () {
      final old = Uint8List(16)..[0] = 2;
      final decoded = PollingConfiguration.fromBytes(old);
      expect(decoded.supportsAdaptive, isFalse);
      expect(decoded.toBytes().length, 16);
      expect(decoded.toBytes()[0], 2);
    });

    test('keeps the 14 byte layout for early firmware', () {
      final early = Uint8List(14)..[0] = 1;
      final decoded = PollingConfiguration.fromBytes(early);
      expect(decoded.toBytes().length, 14);
      expect(decoded.toBytes()[0], 1);
    });

    test('has safe defaults', () {
      final config = PollingConfiguration();
      expect(config.enabled, isFalse);
      expect(config.idleDwellMs, 500);
      expect(config.activeDwellMs, 2000);
    });
  });

  group('PollingRuntimeStatus', () {
    test('decodes phase and hit tracking from the 15 byte layout', () {
      final status = PollingRuntimeStatus.fromBytes(
        Uint8List.fromList([
          1,
          1,
          4,
          1,
          0xE8,
          0x03,
          0,
          0,
          5,
          0,
          1,
          2,
          0x07,
          0x00,
          6,
        ]),
      );
      expect(status.phase, PollingPhase.transaction);
      expect(status.hitCount, 7);
      expect(status.lastHitSlot, 6);

      final none = PollingRuntimeStatus.fromBytes(
        Uint8List.fromList([1, 1, 4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0xFF]),
      );
      expect(none.phase, PollingPhase.idle);
      expect(none.lastHitSlot, isNull);
    });

    test('decodes the little-endian 8 byte layout', () {
      final status = PollingRuntimeStatus.fromBytes(
        Uint8List.fromList([1, 1, 3, 0, 0x34, 0x12, 0x78, 0x56]),
      );
      expect(status.running, isTrue);
      expect(status.currentSlot, 3);
      expect(status.remainingMs, 0x1234);
      expect(status.cycleCount, 0x5678);
      expect(status.wokenByField, isFalse);
    });

    test('decodes the 11 byte layout with 32-bit remaining time', () {
      final status = PollingRuntimeStatus.fromBytes(
        Uint8List.fromList([1, 1, 9, 1, 0xA0, 0x86, 0x01, 0x00, 0x02, 0x00, 1]),
      );
      expect(status.currentSlot, 9);
      expect(status.fieldActive, isTrue);
      expect(status.remainingMs, 100000);
      expect(status.cycleCount, 2);
      expect(status.wokenByField, isTrue);
    });
  });
}
