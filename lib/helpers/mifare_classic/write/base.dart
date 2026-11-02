import 'dart:typed_data';


import 'package:chameleon_ultra_next/core/models/card_info.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/recovery.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/write/gen1.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/write/gen2.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/write/gen3.dart';
import 'package:chameleon_ultra_next/helpers/write.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleon_ultra_next/generated/i18n/app_localizations.dart';

class BaseMifareClassicWriteHelper extends AbstractWriteHelper {
  late MifareClassicRecovery recovery;
  late MifareClassicType type;
  late bool isEV1;
  late bool vanitySak;

  HFCardInfo? hfInfo;
  MifareClassicInfo? mfcInfo;

  @override
  bool get autoDetect => true;

  BaseMifareClassicWriteHelper(super.communicator,
      {required this.recovery,
      this.type = MifareClassicType.m1k,
      this.isEV1 = false});

  @override
  List<AbstractWriteHelper> getAvailableMethods() {
    return [
      MifareClassicGen1WriteHelper(communicator, recovery: recovery),
      MifareClassicGen2WriteHelper(communicator, recovery: recovery),
      MifareClassicGen3WriteHelper(communicator, recovery: recovery)
    ];
  }

  @override
  List<AbstractWriteHelper> getAvailableMethodsByPriority() {
    return [
      MifareClassicGen1WriteHelper(communicator, recovery: recovery),
      MifareClassicGen3WriteHelper(communicator, recovery: recovery),
      MifareClassicGen2WriteHelper(communicator, recovery: recovery)
    ];
  }

  @override
  List<dynamic> getExtraData() {
    return [recovery];
  }

  @override
  Future<void> getCardType() async {
    if (!await communicator.isReaderDeviceMode()) {
      await communicator.setReaderDeviceMode(true);
    }

    var mifare = await communicator.detectMf1Support();
    type = MifareClassicType.none;

    if (mifare) {
      type = await mfClassicGetType(communicator);
    }
  }

  // throw errors if developer is doing something wrong

  Future<Uint8List> readBlock(int block) async {
    throw UnimplementedError();
  }

  Future<bool> writeBlock(int block, Uint8List data) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> isMagic(dynamic data) {
    throw UnimplementedError();
  }

  @override
  bool isReady() {
    throw UnimplementedError();
  }

  @override
  Future<bool> writeData(
      CardSave card, Function(int writeProgress) update) async {
    List<Uint8List> data = card.data;

    if (await communicator.scan14443aTag() == null) {
      return false;
    }

    if (data.isEmpty || data[0].isEmpty) {
      if (data.isEmpty) {
        data = [Uint8List(0)];
      }
      data[0] = createBlock0FromSave(card);
    }

    for (var sector = 0;
        sector < mfClassicGetSectorCount(type, isEV1: isEV1);
        sector++) {
      for (var block = 0;
          block < mfClassicGetBlockCountBySector(sector);
          block++) {
        int blockToWrite = block + mfClassicGetFirstBlockCountBySector(sector);
        if (data.length > blockToWrite && data[blockToWrite].isNotEmpty) {
          if (!(await writeBlock(blockToWrite, data[blockToWrite]))) {
            return false;
          }

          update((blockToWrite / mfClassicGetBlockCount(type) * 100).round());
        }
      }
    }

    return true;
  }

  Uint8List createBlock0FromSave(CardSave card) {
    return mfClassicGenerateFirstBlock(
        hexToBytes(card.uid), card.sak, card.atqa, vanitySak);
  }

  @override
  Future<bool> isCompatible(CardSave card) async {
    CardData? magicCard = await communicator.scan14443aTag();

    if (magicCard == null) {
      return false;
    }

    if (magicCard.uid.length != hexToBytes(card.uid).length) {
      return false;
    }

    int blockCount =
        mfClassicGetBlockCount(chameleonTagTypeGetMfClassicType(card.tag));
    blockCount--;

    Uint8List data = await communicator.send14ARaw(
        Uint8List.fromList([0x60, blockCount]),
        checkResponseCrc: false);

    if (data.length != 4) {
      return false;
    }

    return true;
  }

  @override
  Future<void> reset() async {
    hfInfo = null;
    mfcInfo = null;
  }

}
