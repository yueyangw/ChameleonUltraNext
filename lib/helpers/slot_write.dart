import 'dart:typed_data';

import 'package:chameleon_ultra_next/bridge/chameleon.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/helpers/hf14a4_slot.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_ultralight/general.dart';
import 'package:chameleon_ultra_next/helpers/slot_dump.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';

/// Reads the card configured for [frequency] on [slot] into a [CardSave].
///
/// The slot is activated first because the emulator commands operate on the
/// currently active slot.
Future<CardSave> readCardSaveFromSlot(
  ChameleonCommunicator comm,
  int slot,
  TagFrequency frequency,
  TagType type,
  String name,
) async {
  await comm.activateSlot(slot);

  if (frequency == TagFrequency.lf) {
    final card = await _readLfCard(comm, type);
    return CardSave(
      uid: card.toString(),
      name: name,
      tag: type,
    );
  }

  if (isMifareClassic(type) || isMifareUltralight(type)) {
    return readHfDumpFromSlot(comm, name, type);
  }
  final identity = await readHf14a4SlotIdentity(comm, name);
  identity.tag = type;
  return identity;
}

/// Writes [card] into [slot]: sets the slot type, uploads the data, names the
/// slot and persists everything. [onProgress] reports 0..100 for HF dumps.
Future<void> writeCardSaveToSlot(
  ChameleonCommunicator comm,
  int slot,
  CardSave card, {
  void Function(int progress)? onProgress,
}) async {
  final frequency = chameleonTagToFrequency(card.tag);

  await comm.activateSlot(slot);
  await comm.setSlotType(slot, card.tag);
  await comm.setDefaultDataToSlot(slot, card.tag);

  if (frequency == TagFrequency.lf) {
    await _writeLfCard(comm, card);
    await comm.saveSlotData();
  } else {
    await writeHf14a4SlotIdentity(comm, card);
    final hasDump = (isMifareClassic(card.tag) || isMifareUltralight(card.tag)) &&
        card.data.isNotEmpty;
    if (hasDump) {
      // Also activates the slot and persists the slot data when done.
      await writeHfDumpToSlot(comm, slot, card.tag, card.data,
          onProgress: onProgress);
    } else {
      await comm.saveSlotData();
    }
  }

  if (card.name.isNotEmpty) {
    await comm.setSlotTagName(slot, card.name, frequency);
  }
}

/// True when [card] can be replaced into a slot of the given [frequency].
bool cardMatchesFrequency(CardSave card, TagFrequency frequency) =>
    chameleonTagToFrequency(card.tag) == frequency;

Future<LFCard> _readLfCard(ChameleonCommunicator comm, TagType type) async {
  switch (type) {
    case TagType.hidProx:
      return comm.getHIDProxEmulatorID();
    case TagType.viking:
      return comm.getVikingEmulatorID();
    case TagType.pac:
      return comm.getPacEmulatorID();
    case TagType.ioProx:
      return comm.getIoProxEmulatorID();
    case TagType.jablotron:
      return comm.getJablotronEmulatorID();
    case TagType.idteck:
      return comm.getIdteckEmulatorID();
    default:
      return EM410XCard(type: type, uid: await comm.getEM410XEmulatorID());
  }
}

Future<void> _writeLfCard(ChameleonCommunicator comm, CardSave card) async {
  final Uint8List bytes = hexToBytes(card.uid);
  switch (card.tag) {
    case TagType.hidProx:
      return comm.setHIDProxEmulatorID(bytes);
    case TagType.viking:
      return comm.setVikingEmulatorID(bytes);
    case TagType.pac:
      return comm.setPacEmulatorID(bytes);
    case TagType.ioProx:
      return comm.setIoProxEmulatorID(bytes);
    case TagType.jablotron:
      return comm.setJablotronEmulatorID(bytes);
    case TagType.idteck:
      return comm.setIdteckEmulatorID(bytes);
    default:
      return comm.setEM410XEmulatorID(bytes);
  }
}
