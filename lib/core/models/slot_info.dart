import 'dart:typed_data';

import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';

/// Extended slot metadata exposed by the custom 16-slot firmware.
class SlotInfo {
  final int index;
  TagType hf;
  TagType lf;
  bool enabledHf;
  bool enabledLf;
  String hfName;
  String lfName;

  SlotInfo({
    required this.index,
    this.hf = TagType.unknown,
    this.lf = TagType.unknown,
    this.enabledHf = false,
    this.enabledLf = false,
    this.hfName = '',
    this.lfName = '',
  });

  bool get hasHf => hf != TagType.unknown;
  bool get hasLf => lf != TagType.unknown;
  bool get anyEnabled => enabledHf || enabledLf;
  bool get empty => !hasHf && !hasLf;
}

/// Configuration of the firmware-side polling engine.
class PollingConfiguration {
  bool enabled;
  int slotMask;
  int idleDwellMs;
  int activeDwellMs;
  int cooldownMs;
  bool adaptive;
  int jitterPercent;
  int order;
  bool keepAwake;

  /// HF only: keep the current slot while the reader is mid-transaction, up
  /// to this many milliseconds (0 = off).
  int txnHoldMs;

  /// HF only: extra dwell granted to a slot the reader just selected
  /// (0 = off).
  int hitBonusMs;

  /// HF only: how much a slot that was visited while a field was present but
  /// never got selected has its next field dwell shortened, in percent
  /// (0 = off, max 50).
  int missShrinkPct;

  /// Wire layout reported by the firmware: 14 bytes / version 1 on early
  /// builds, 16 bytes / version 2 once the record was padded to a word and
  /// 24 bytes / version 3 with transaction hold and hit tracking.
  int wireLength;

  PollingConfiguration({
    this.enabled = false,
    this.slotMask = 0,
    this.idleDwellMs = 500,
    this.activeDwellMs = 2000,
    this.cooldownMs = 200,
    this.adaptive = true,
    this.jitterPercent = 10,
    this.order = 0,
    this.keepAwake = true,
    this.txnHoldMs = 1500,
    this.hitBonusMs = 1000,
    this.missShrinkPct = 25,
    this.wireLength = 24,
  });

  /// True when the firmware understands transaction hold / hit tracking.
  bool get supportsAdaptive => wireLength >= 24;

  factory PollingConfiguration.fromBytes(Uint8List bytes) {
    if (bytes.length < 14) {
      return PollingConfiguration();
    }
    return PollingConfiguration(
      enabled: bytes[1] != 0,
      slotMask: bytes[2] | (bytes[3] << 8),
      idleDwellMs: bytes[4] | (bytes[5] << 8),
      activeDwellMs: bytes[6] | (bytes[7] << 8),
      cooldownMs: bytes[8] | (bytes[9] << 8),
      adaptive: bytes[10] != 0,
      jitterPercent: bytes[11],
      order: bytes[12],
      keepAwake: bytes[13] != 0,
      txnHoldMs: bytes.length >= 24 ? bytes[14] | (bytes[15] << 8) : 0,
      hitBonusMs: bytes.length >= 24 ? bytes[16] | (bytes[17] << 8) : 0,
      missShrinkPct: bytes.length >= 24 ? bytes[18] : 0,
      wireLength: bytes.length >= 24 ? 24 : (bytes.length >= 16 ? 16 : 14),
    );
  }

  Uint8List toBytes() {
    final b = Uint8List(wireLength);
    b[0] = wireLength >= 24 ? 3 : (wireLength >= 16 ? 2 : 1);
    b[1] = enabled ? 1 : 0;
    b[2] = slotMask & 0xFF;
    b[3] = (slotMask >> 8) & 0xFF;
    b[4] = idleDwellMs & 0xFF;
    b[5] = (idleDwellMs >> 8) & 0xFF;
    b[6] = activeDwellMs & 0xFF;
    b[7] = (activeDwellMs >> 8) & 0xFF;
    b[8] = cooldownMs & 0xFF;
    b[9] = (cooldownMs >> 8) & 0xFF;
    b[10] = adaptive ? 1 : 0;
    b[11] = jitterPercent;
    b[12] = order;
    b[13] = keepAwake ? 1 : 0;
    if (wireLength >= 24) {
      b[14] = txnHoldMs & 0xFF;
      b[15] = (txnHoldMs >> 8) & 0xFF;
      b[16] = hitBonusMs & 0xFF;
      b[17] = (hitBonusMs >> 8) & 0xFF;
      b[18] = missShrinkPct;
    }
    return b;
  }

  PollingConfiguration copy() => PollingConfiguration(
    enabled: enabled,
    slotMask: slotMask,
    idleDwellMs: idleDwellMs,
    activeDwellMs: activeDwellMs,
    cooldownMs: cooldownMs,
    adaptive: adaptive,
    jitterPercent: jitterPercent,
    order: order,
    keepAwake: keepAwake,
    txnHoldMs: txnHoldMs,
    hitBonusMs: hitBonusMs,
    missShrinkPct: missShrinkPct,
    wireLength: wireLength,
  );
}

/// What the poller currently sees on the reader side.
enum PollingPhase {
  idle,
  field,
  transaction,
  cooldown;

  static PollingPhase fromValue(int value) =>
      value >= 0 && value < PollingPhase.values.length
      ? PollingPhase.values[value]
      : PollingPhase.idle;
}

class PollingRuntimeStatus {
  final bool enabled;
  final bool running;
  final int currentSlot;
  final bool fieldActive;
  final int remainingMs;
  final int cycleCount;
  final bool wokenByField;

  /// Sensing phase reported by the firmware.
  final PollingPhase phase;

  /// Reader selections of the emulated card since power-up.
  final int hitCount;

  /// Slot that was selected last, or null if none yet.
  final int? lastHitSlot;

  const PollingRuntimeStatus({
    this.enabled = false,
    this.running = false,
    this.currentSlot = 0,
    this.fieldActive = false,
    this.remainingMs = 0,
    this.cycleCount = 0,
    this.wokenByField = false,
    this.phase = PollingPhase.idle,
    this.hitCount = 0,
    this.lastHitSlot,
  });

  /// The firmware sends this struct in native (little-endian) byte order.
  /// Early builds used a 8-byte layout with a 16-bit `remaining_ms`; newer
  /// ones use 11 bytes with a 32-bit `remaining_ms` and a trailing
  /// `woken_by_field` flag.
  factory PollingRuntimeStatus.fromBytes(Uint8List bytes) {
    if (bytes.length < 8) {
      return const PollingRuntimeStatus();
    }
    final view = ByteData.sublistView(bytes);
    final extended = bytes.length >= 11;
    return PollingRuntimeStatus(
      enabled: bytes[0] != 0,
      running: bytes[1] != 0,
      currentSlot: bytes[2],
      fieldActive: bytes[3] != 0,
      remainingMs: extended
          ? view.getUint32(4, Endian.little)
          : view.getUint16(4, Endian.little),
      cycleCount: view.getUint16(extended ? 8 : 6, Endian.little),
      wokenByField: extended && bytes[10] != 0,
      phase: bytes.length >= 15
          ? PollingPhase.fromValue(bytes[11])
          : (bytes[3] != 0 ? PollingPhase.field : PollingPhase.idle),
      hitCount: bytes.length >= 15 ? view.getUint16(12, Endian.little) : 0,
      lastHitSlot: bytes.length >= 15 && bytes[14] != 0xFF ? bytes[14] : null,
    );
  }
}

/// A saved card/dump in the local wallet.
class WalletCard {
  String id;
  String name;
  String uid;
  int sak;
  Uint8List atqa;
  Uint8List ats;
  TagType tag;
  List<Uint8List> data;
  String? folderId;
  int createdAtMs;
  int updatedAtMs;

  WalletCard({
    String? id,
    required this.name,
    required this.uid,
    required this.tag,
    this.sak = 0,
    Uint8List? atqa,
    Uint8List? ats,
    this.data = const [],
    this.folderId,
    int? createdAtMs,
    int? updatedAtMs,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       atqa = atqa ?? Uint8List(0),
       ats = ats ?? Uint8List(0),
       createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
       updatedAtMs = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'uid': uid,
    'sak': sak,
    'atqa': atqa.toList(),
    'ats': ats.toList(),
    'tag': tag.value,
    'data': data.map((e) => e.toList()).toList(),
    if (folderId != null) 'folderId': folderId,
    'createdAtMs': createdAtMs,
    'updatedAtMs': updatedAtMs,
  };

  factory WalletCard.fromJson(Map<String, dynamic> json) => WalletCard(
    id: json['id'] as String?,
    name: (json['name'] as String?) ?? 'Unnamed card',
    uid: (json['uid'] as String?) ?? '',
    sak: (json['sak'] as int?) ?? 0,
    atqa: Uint8List.fromList(
      List<int>.from((json['atqa'] as List<dynamic>?) ?? const []),
    ),
    ats: Uint8List.fromList(
      List<int>.from((json['ats'] as List<dynamic>?) ?? const []),
    ),
    tag: getTagTypeByValue((json['tag'] as int?) ?? 0),
    data: ((json['data'] as List<dynamic>?) ?? const [])
        .map((e) => Uint8List.fromList(List<int>.from(e as List)))
        .toList(),
    folderId: json['folderId'] as String?,
    createdAtMs: json['createdAtMs'] as int?,
    updatedAtMs: json['updatedAtMs'] as int?,
  );

  WalletCard copyWith({
    String? name,
    TagType? tag,
    String? uid,
    List<Uint8List>? data,
  }) => WalletCard(
    id: id,
    name: name ?? this.name,
    uid: uid ?? this.uid,
    tag: tag ?? this.tag,
    sak: sak,
    atqa: atqa,
    ats: ats,
    data: data ?? this.data,
    folderId: folderId,
    createdAtMs: createdAtMs,
    updatedAtMs: DateTime.now().millisecondsSinceEpoch,
  );
}
