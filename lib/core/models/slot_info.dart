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
  });

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
    );
  }

  Uint8List toBytes() {
    final b = Uint8List(14);
    b[0] = 1;
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
      );
}

class PollingRuntimeStatus {
  final bool enabled;
  final bool running;
  final int currentSlot;
  final bool fieldActive;
  final int remainingMs;
  final int cycleCount;

  const PollingRuntimeStatus({
    this.enabled = false,
    this.running = false,
    this.currentSlot = 0,
    this.fieldActive = false,
    this.remainingMs = 0,
    this.cycleCount = 0,
  });

  factory PollingRuntimeStatus.fromBytes(Uint8List bytes) {
    if (bytes.length < 8) {
      return const PollingRuntimeStatus();
    }
    return PollingRuntimeStatus(
      enabled: bytes[0] != 0,
      running: bytes[1] != 0,
      currentSlot: bytes[2],
      fieldActive: bytes[3] != 0,
      remainingMs: (bytes[4] << 8) | bytes[5],
      cycleCount: (bytes[6] << 8) | bytes[7],
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
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
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
            List<int>.from((json['atqa'] as List<dynamic>?) ?? const [])),
        ats: Uint8List.fromList(
            List<int>.from((json['ats'] as List<dynamic>?) ?? const [])),
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
  }) =>
      WalletCard(
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
