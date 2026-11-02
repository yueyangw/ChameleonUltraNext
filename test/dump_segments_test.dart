import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/dump_segments.dart';

Uint8List _bytes(int length, [int fill = 0]) =>
    Uint8List.fromList(List.filled(length, fill));

void main() {
  group('classicBlockSegments', () {
    test('splits block 0 for a 4 byte UID', () {
      final segments =
          classicBlockSegments(block: 0, data: _bytes(16), uidLength: 4);
      expect(segments.map((s) => s.role), [
        DumpRole.uid,
        DumpRole.bcc,
        DumpRole.sak,
        DumpRole.atqa,
        DumpRole.manufacturer,
      ]);
      expect(segments.first.end, 4);
    });

    test('splits block 0 for a 7 byte UID without BCC', () {
      final segments =
          classicBlockSegments(block: 0, data: _bytes(16), uidLength: 7);
      expect(segments.map((s) => s.role), [
        DumpRole.uid,
        DumpRole.sak,
        DumpRole.atqa,
        DumpRole.manufacturer,
      ]);
      expect(segments.first.end, 7);
    });

    test('recognises trailers of small and large sectors', () {
      for (final block in [3, 7, 63, 127, 143, 255]) {
        expect(classicIsTrailer(block), isTrue, reason: 'block $block');
        expect(
          classicBlockSegments(block: block, data: _bytes(16)).map((s) => s.role),
          [DumpRole.keyA, DumpRole.access, DumpRole.gpb, DumpRole.keyB],
        );
      }
      for (final block in [1, 2, 4, 128, 140, 254]) {
        expect(classicIsTrailer(block), isFalse, reason: 'block $block');
      }
    });

    test('marks valid value blocks', () {
      // value 1, address 5
      final value = Uint8List.fromList([
        1, 0, 0, 0, 0xFE, 0xFF, 0xFF, 0xFF, 1, 0, 0, 0, 5, 0xFA, 5, 0xFA
      ]);
      expect(classicBlockSegments(block: 1, data: value).single.role,
          DumpRole.value);
      expect(classicBlockSegments(block: 1, data: _bytes(16, 0xAA)).single.role,
          DumpRole.data);
    });
  });

  group('ultralightPageSegments', () {
    test('marks UID, lock bytes and OTP on the first pages', () {
      final data = _bytes(4);
      expect(
          ultralightPageSegments(tag: TagType.ntag213, page: 0, data: data)
              .map((s) => s.role),
          [DumpRole.uid, DumpRole.bcc]);
      expect(
          ultralightPageSegments(tag: TagType.ntag213, page: 2, data: data)
              .map((s) => s.role),
          [DumpRole.bcc, DumpRole.data, DumpRole.lock]);
      expect(
          ultralightPageSegments(tag: TagType.ntag213, page: 3, data: data)
              .single
              .role,
          DumpRole.otp);
    });

    test('marks configuration, password and PACK pages of NTAG213', () {
      final data = _bytes(4);
      DumpRole roleOf(int page) =>
          ultralightPageSegments(tag: TagType.ntag213, page: page, data: data)
              .first
              .role;
      expect(roleOf(41), DumpRole.config);
      expect(roleOf(42), DumpRole.config);
      expect(roleOf(43), DumpRole.password);
      expect(roleOf(44), DumpRole.password);
      expect(roleOf(10), DumpRole.data);
    });
  });

  test('classicBcc xors the UID bytes', () {
    expect(classicBcc([0x52, 0x40, 0xAD, 0xED]), 0x52 ^ 0x40 ^ 0xAD ^ 0xED);
  });

  test('bytesToAscii masks non printable bytes', () {
    expect(bytesToAscii(Uint8List.fromList([0x41, 0x00, 0x7F, 0x62])), 'A..b');
  });
}
