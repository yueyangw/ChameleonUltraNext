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
///
/// The engine swaps the emulated slot according to what the reader does with
/// the card; the waits below only tell it how patient to be.
class PollingConfiguration {
  bool enabled;
  int slotMask;

  /// Slot rotation while no field is present.
  int idleDwellMs;

  /// Slot rotation while a field is present but the reader sends no REQA/WUPA
  /// (for example an LF field).
  int activeDwellMs;
  int cooldownMs;
  bool adaptive;
  int jitterPercent;
  int order;
  bool keepAwake;

  /// UID-only reader: silence after the last read before the slot is left.
  int doneQuietMs;

  /// MIFARE auth failed and the reader went silent (a phone handing the tag
  /// to an app): how long the slot is kept.
  int patienceMs;

  /// The reader pauses its field and comes back (a phone every ~2 s): the
  /// slot it worked on is kept for this many sessions (0 = off).
  int stickySessions;

  /// MIFARE auth failed and the reader only looks for other cards: the slot
  /// is left after this much silence.
  int failPollQuietMs;

  /// UID-only reader: extra reads of a card per slot (reads = 1 + this).
  int representCount;

  /// Failed MIFARE auths without a success that end a visit (0 = off).
  int authFailCount;

  /// A slot with a successful auth is released after this much silence.
  int lockQuietMs;

  /// Wire layout reported by the firmware: 14 bytes / version 1 on early
  /// builds, 16 bytes / version 2, 24 bytes from version 3. Versions 3 to 6
  /// belong to the timer based engines, 7 to the reader driven one.
  int wireLength;
  int version;

  /// Bytes 14.. of an older record, written back unchanged.
  final Uint8List legacyTail;

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
    this.doneQuietMs = 100,
    this.patienceMs = 800,
    this.stickySessions = 3,
    this.failPollQuietMs = 150,
    this.representCount = 1,
    this.authFailCount = 3,
    this.lockQuietMs = 1000,
    this.wireLength = 24,
    this.version = 7,
    Uint8List? legacyTail,
  }) : legacyTail = legacyTail ?? Uint8List(0);

  /// True when the firmware has the reader driven engine.
  bool get supportsReaderAware => wireLength >= 24 && version >= 7;

  /// Kept for the older checks: the reader driven engine includes everything.
  bool get supportsAdaptive => supportsReaderAware;

  factory PollingConfiguration.fromBytes(Uint8List bytes) {
    if (bytes.length < 14) {
      return PollingConfiguration();
    }
    final modern = bytes.length >= 24 && bytes[0] >= 7;
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
      doneQuietMs: modern ? bytes[14] | (bytes[15] << 8) : 100,
      patienceMs: modern ? bytes[16] | (bytes[17] << 8) : 800,
      stickySessions: modern ? bytes[18] : 3,
      failPollQuietMs: modern ? bytes[19] | (bytes[20] << 8) : 150,
      representCount: modern ? bytes[21] : 1,
      authFailCount: modern ? bytes[22] : 3,
      lockQuietMs: modern ? bytes[23] * 100 : 1000,
      wireLength: bytes.length >= 24 ? 24 : (bytes.length >= 16 ? 16 : 14),
      version: bytes.length >= 24 ? bytes[0] : bytes[0],
      legacyTail: Uint8List.fromList(bytes.sublist(14)),
    );
  }

  Uint8List toBytes() {
    final b = Uint8List(wireLength);
    b[0] = version;
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
    if (supportsReaderAware) {
      b[14] = doneQuietMs & 0xFF;
      b[15] = (doneQuietMs >> 8) & 0xFF;
      b[16] = patienceMs & 0xFF;
      b[17] = (patienceMs >> 8) & 0xFF;
      b[18] = stickySessions;
      b[19] = failPollQuietMs & 0xFF;
      b[20] = (failPollQuietMs >> 8) & 0xFF;
      b[21] = representCount;
      b[22] = authFailCount;
      b[23] = (lockQuietMs ~/ 100).clamp(1, 100);
    } else {
      for (var i = 0; i < legacyTail.length && 14 + i < b.length; i++) {
        b[14 + i] = legacyTail[i];
      }
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
    doneQuietMs: doneQuietMs,
    patienceMs: patienceMs,
    stickySessions: stickySessions,
    failPollQuietMs: failPollQuietMs,
    representCount: representCount,
    authFailCount: authFailCount,
    lockQuietMs: lockQuietMs,
    wireLength: wireLength,
    version: version,
    legacyTail: legacyTail,
  );
}

/// What the poller currently sees on the reader side.
enum PollingPhase {
  idle,
  field,
  hold,
  cooldown,
  gap;

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

  /// Slots skipped after a failed MIFARE Classic auth in this run.
  final int badMask;

  /// Re-presentations left in this turn of the current slot.
  final int representsLeft;

  /// Reader poll period estimated from its REQA/WUPA interval, null if unknown.
  final int? pollPeriodMs;

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
    this.badMask = 0,
    this.representsLeft = 0,
    this.pollPeriodMs,
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
      badMask: bytes.length >= 18 ? view.getUint16(15, Endian.little) : 0,
      representsLeft: bytes.length >= 18 ? bytes[17] : 0,
      pollPeriodMs: bytes.length >= 20 && view.getUint16(18, Endian.little) != 0
          ? view.getUint16(18, Endian.little)
          : null,
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
