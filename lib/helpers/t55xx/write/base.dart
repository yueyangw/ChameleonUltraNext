import 'package:chameleon_ultra_next/core/models/card_info.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/helpers/validators.dart';
import 'package:chameleon_ultra_next/helpers/write.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleon_ultra_next/generated/i18n/app_localizations.dart';
import 'package:flutter/services.dart';

class BaseT55XXCardHelper extends AbstractWriteHelper {
  LFCardInfo? lfInfo;

  @override
  bool get autoDetect => true;

  @override
  String get name => "t55xx";

  static String get staticName => "t55xx";
  TextEditingController newKeyController = TextEditingController();
  TextEditingController currentKeyController = TextEditingController();
  String currentKey = "";
  String newKey = "";

  BaseT55XXCardHelper(super.communicator);

  @override
  List<AbstractWriteHelper> getAvailableMethods() {
    return [
      BaseT55XXCardHelper(communicator),
    ];
  }

  @override
  List<AbstractWriteHelper> getAvailableMethodsByPriority() {
    return [BaseT55XXCardHelper(communicator)];
  }

  @override
  Future<bool> isCompatible(CardSave card) async {
    return true;
  }

  @override
  Future<bool> isMagic(data) async {
    return false;
  }

  @override
  bool isReady() {
    return currentKey.length == 8 && newKey.length == 8;
  }

  @override
  bool writeWidgetSupported() {
    return true;
  }

  @override
  Future<void> reset() async {
    currentKey = "";
    newKey = "";
  }

  @override
  Future<bool> writeData(
      CardSave card, Function(int writeProgress) update) async {
    if (isEM410X(card.tag)) {
      await communicator.writeEM410XtoT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]);
      await Future.delayed(const Duration(milliseconds: 500));
      var newCard = await communicator.readEM410X();
      return newCard.toString() == card.uid;
    } else if (card.tag == TagType.hidProx) {
      await communicator.writeHIDProxToT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]);
      await Future.delayed(const Duration(milliseconds: 500));
      var newCard = await communicator.readHIDProx();
      return newCard.toString() == card.uid;
    } else if (card.tag == TagType.viking) {
      await communicator.writeVikingToT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]);
      await Future.delayed(const Duration(milliseconds: 500));
      var newCard = await communicator.readViking();
      return newCard.toString() == card.uid;
    } else if (card.tag == TagType.jablotron) {
      await communicator.writeJablotronToT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]);
      await Future.delayed(const Duration(milliseconds: 500));
      var newCard = await communicator.readJablotron();
      return newCard?.toString() == bytesToHexSpace(hexToBytes(card.uid));
    } else if (card.tag == TagType.pac) {
      await communicator.writePacToT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]);
      var newCard = await communicator.readPac();
      return newCard.toString() == card.uid;
    } else if (card.tag == TagType.ioProx) {
      await communicator.writeIoProxToT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]);
      await Future.delayed(const Duration(milliseconds: 500));
      var newCard = await communicator.readIoProx();
      return newCard.toString() == card.uid;
    } else if (card.tag == TagType.idteck) {
      await communicator.writeIdteckToT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]);
      // IDTECK read is not implemented in the firmware (PSK demodulation
      // on the envelope-only tag-emulation ADC path is a follow-up), so we
      // cannot read back the tag for verification. Assume the T55xx write
      // succeeded if the firmware did not raise an error.
      return true;
    }

    return false;
  }
}
