import 'package:chameleon_ultra_next/bridge/chameleon.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/recovery/recovery.dart' as recovery;
import 'package:chameleon_ultra_next/recovery/recovery.dart' show Mfkey32Dart;

/// A key recovered from a pair of detected reader authentications.
class RecoveredKey {
  final int uid;
  final int block;
  final String keyType; // 'A' or 'B'
  final String key; // 12 upper-case hex chars

  const RecoveredKey({
    required this.uid,
    required this.block,
    required this.keyType,
    required this.key,
  });

  String get uidHex => uid.toRadixString(16).padLeft(8, '0').toUpperCase();

  @override
  String toString() => 'UID $uidHex · 块 $block · Key$keyType · $key';
}

/// Runs mfkey32 over every pair of nonces recorded by the MF1 detection
/// feature. When [uidFilter] is given only authentications against that
/// 4-byte UID are used (the detection log is device-wide, not per slot).
Future<List<RecoveredKey>> recoverMfkey32(
  ChameleonCommunicator comm,
  int count, {
  int? uidFilter,
  void Function(RecoveredKey key)? onKey,
}) async {
  final found = <RecoveredKey>[];
  final detections = await comm.getMf1DetectionResult(count);
  for (final uidEntry in detections.entries) {
    if (uidFilter != null && uidEntry.key != uidFilter) continue;
    for (final blockEntry in uidEntry.value.entries) {
      for (final typeEntry in blockEntry.value.entries) {
        final values = typeEntry.value;
        for (var i = 0; i < values.length; i++) {
          for (var j = i + 1; j < values.length; j++) {
            final key = await recovery.mfkey32(Mfkey32Dart(
              uid: uidEntry.key,
              nt0: values[i].nt,
              nt1: values[j].nt,
              nr0Enc: values[i].nr,
              ar0Enc: values[i].ar,
              nr1Enc: values[j].nr,
              ar1Enc: values[j].ar,
            ));
            final text = key
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join()
                .toUpperCase();
            final result = RecoveredKey(
              uid: uidEntry.key,
              block: blockEntry.key,
              keyType: typeEntry.key,
              key: text,
            );
            found.add(result);
            onKey?.call(result);
          }
        }
      }
    }
  }
  return found;
}

/// First four UID bytes as the big-endian integer the detection log uses.
int? detectionUidOf(String spacedHexUid) {
  final bytes = hexToBytes(spacedHexUid);
  if (bytes.length < 4) return null;
  // 7-byte UIDs authenticate with the last four bytes.
  final tail = bytes.sublist(bytes.length - 4);
  return (tail[0] << 24) | (tail[1] << 16) | (tail[2] << 8) | tail[3];
}
