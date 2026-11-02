import 'package:flutter_test/flutter_test.dart';

import 'package:charmeleon_ultra_next/core/models/card_info.dart';

void main() {
  group('HFCardInfo', () {
    test('defaults to an unknown tag with no UID', () {
      final info = HFCardInfo();

      expect(info.uid, isEmpty);
      expect(info.sak, isEmpty);
      expect(info.atqa, isEmpty);
      expect(info.ats, isEmpty);
      expect(info.tech, isEmpty);
      expect(info.type, TagType.unknown);
      expect(info.cardExist, isTrue);
    });
  });

  group('MifareClassicInfo', () {
    test('starts in the idle state', () {
      final info = MifareClassicInfo();

      expect(info.state, MifareClassicState.none);
      expect(info.type, MifareClassicType.none);
      expect(info.isEV1, isFalse);
      expect(info.recovery, isNull);
    });
  });

  group('LFCardInfo', () {
    test('has no card by default', () {
      final info = LFCardInfo();

      expect(info.card, isNull);
      expect(info.cardExist, isTrue);
    });
  });
}
