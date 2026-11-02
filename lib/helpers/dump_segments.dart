import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/dump_analyzer.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_ultralight/general.dart';

/// What a run of bytes inside a dump block means.
enum DumpRole {
  uid('UID'),
  bcc('BCC'),
  sak('SAK'),
  atqa('ATQA'),
  manufacturer('厂商数据'),
  keyA('Key A'),
  access('访问位'),
  gpb('GPB'),
  keyB('Key B'),
  value('数值块'),
  lock('锁定位'),
  otp('OTP/CC'),
  password('密码/PACK'),
  config('配置'),
  data('数据');

  const DumpRole(this.label);
  final String label;

  Color color(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    MaterialColor base;
    switch (this) {
      case DumpRole.uid:
        base = Colors.purple;
      case DumpRole.bcc:
        base = Colors.orange;
      case DumpRole.sak:
        base = Colors.teal;
      case DumpRole.atqa:
        base = Colors.cyan;
      case DumpRole.manufacturer:
        base = Colors.blueGrey;
      case DumpRole.keyA:
        base = Colors.lightGreen;
      case DumpRole.access:
        base = Colors.deepOrange;
      case DumpRole.gpb:
        base = Colors.brown;
      case DumpRole.keyB:
        base = Colors.green;
      case DumpRole.value:
        base = Colors.amber;
      case DumpRole.lock:
        base = Colors.red;
      case DumpRole.otp:
        base = Colors.pink;
      case DumpRole.password:
        base = Colors.lightGreen;
      case DumpRole.config:
        base = Colors.indigo;
      case DumpRole.data:
        return Colors.transparent;
    }
    return dark ? base.shade300 : base.shade700;
  }
}

/// Half-open byte range `[start, end)` of a block that plays [role].
class DumpSegment {
  final int start;
  final int end;
  final DumpRole role;

  const DumpSegment(this.start, this.end, this.role);

  int get length => end - start;

  @override
  String toString() => '$role[$start,$end)';
}

/// Splits one 16 byte MIFARE Classic block into its meaningful parts.
///
/// [uidLength] is 4 or 7 (single or double size UID) and only matters for
/// block 0.
List<DumpSegment> classicBlockSegments({
  required int block,
  required Uint8List data,
  int uidLength = 4,
}) {
  if (data.length != 16) {
    return [DumpSegment(0, data.length, DumpRole.data)];
  }
  if (block == 0) {
    return uidLength == 7
        ? const [
            DumpSegment(0, 7, DumpRole.uid),
            DumpSegment(7, 8, DumpRole.sak),
            DumpSegment(8, 10, DumpRole.atqa),
            DumpSegment(10, 16, DumpRole.manufacturer),
          ]
        : const [
            DumpSegment(0, 4, DumpRole.uid),
            DumpSegment(4, 5, DumpRole.bcc),
            DumpSegment(5, 6, DumpRole.sak),
            DumpSegment(6, 8, DumpRole.atqa),
            DumpSegment(8, 16, DumpRole.manufacturer),
          ];
  }
  if (classicIsTrailer(block)) {
    return const [
      DumpSegment(0, 6, DumpRole.keyA),
      DumpSegment(6, 9, DumpRole.access),
      DumpSegment(9, 10, DumpRole.gpb),
      DumpSegment(10, 16, DumpRole.keyB),
    ];
  }
  if (classicIsValueBlock(data)) {
    return const [DumpSegment(0, 16, DumpRole.value)];
  }
  return const [DumpSegment(0, 16, DumpRole.data)];
}

/// True for the last block of a MIFARE Classic sector.
bool classicIsTrailer(int block) {
  final sector = mfClassicGetSectorByBlock(block);
  return mfClassicGetSectorTrailerBlockBySector(sector) == block;
}

bool classicIsValueBlock(Uint8List data) =>
    data.length == 16 &&
    MifareClassicDumpAnalyzer.valueBlockToInt(bytesToUpperHex(data)) != null;

/// Splits one 4 byte MIFARE Ultralight / NTAG page into its meaningful parts.
List<DumpSegment> ultralightPageSegments({
  required TagType tag,
  required int page,
  required Uint8List data,
}) {
  if (data.length != 4) {
    return [DumpSegment(0, data.length, DumpRole.data)];
  }
  if (page == 0) {
    return const [
      DumpSegment(0, 3, DumpRole.uid),
      DumpSegment(3, 4, DumpRole.bcc),
    ];
  }
  if (page == 1) {
    return const [DumpSegment(0, 4, DumpRole.uid)];
  }
  if (page == 2) {
    return const [
      DumpSegment(0, 1, DumpRole.bcc),
      DumpSegment(1, 2, DumpRole.data),
      DumpSegment(2, 4, DumpRole.lock),
    ];
  }
  if (page == 3) {
    return const [DumpSegment(0, 4, DumpRole.otp)];
  }
  if (mfUltralightGetKeyPages(tag).contains(page)) {
    return const [DumpSegment(0, 4, DumpRole.password)];
  }
  final passwordPage = mfUltralightGetPasswordPage(tag);
  if (passwordPage != 0) {
    if (page == passwordPage) {
      return const [DumpSegment(0, 4, DumpRole.password)];
    }
    if (page == passwordPage + 1) {
      return const [
        DumpSegment(0, 2, DumpRole.password),
        DumpSegment(2, 4, DumpRole.data),
      ];
    }
    if (page == passwordPage - 1 || page == passwordPage - 2) {
      return const [DumpSegment(0, 4, DumpRole.config)];
    }
  }
  return const [DumpSegment(0, 4, DumpRole.data)];
}

/// A short human readable label for what [page] / [block] contains, or null.
String? classicBlockCaption(int block, {int uidLength = 4}) {
  if (block == 0) return '厂商块';
  if (classicIsTrailer(block)) return '扇区尾块';
  return null;
}

String? ultralightPageCaption(TagType tag, int page) {
  switch (page) {
    case 0:
      return 'UID / BCC0';
    case 1:
      return 'UID';
    case 2:
      return 'BCC1 / 锁定位';
    case 3:
      return 'OTP / CC';
  }
  if (mfUltralightGetKeyPages(tag).contains(page)) return '密钥';
  final passwordPage = mfUltralightGetPasswordPage(tag);
  if (passwordPage != 0) {
    if (page == passwordPage) return '密码 PWD';
    if (page == passwordPage + 1) return 'PACK';
    if (page == passwordPage - 2) return '配置 CFG0';
    if (page == passwordPage - 1) return '配置 CFG1';
  }
  return null;
}

String bytesToUpperHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

String byteToHex(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();

/// Printable ASCII rendering of [bytes] (non printable bytes become '.').
String bytesToAscii(Uint8List bytes) =>
    String.fromCharCodes(bytes.map((b) => b >= 32 && b <= 126 ? b : 0x2E));

/// The BCC check byte for a 4 byte UID.
int classicBcc(List<int> uid4) =>
    uid4.take(4).fold<int>(0, (acc, b) => acc ^ b) & 0xFF;
