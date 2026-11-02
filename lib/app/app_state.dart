import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'package:chameleon_ultra_next/bridge/chameleon.dart';
import 'package:chameleon_ultra_next/connector/serial_abstract.dart';
import 'package:chameleon_ultra_next/core/models/slot_info.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';

/// Global application state shared through the widget tree via `provider`.
///
/// Keeps the transport, cached device metadata and the custom polling
/// configuration in one place so every screen stays in sync.
class ChameleonGUIState extends ChangeNotifier {
  final SharedPreferencesProvider sharedPreferencesProvider;
  ChameleonGUIState(this.sharedPreferencesProvider);

  Logger? log;
  AbstractSerial? connector;
  ChameleonCommunicator? communicator;

  bool devMode = false;
  bool easterFlagPlaceholder = false;
  bool easterEgg = false;
  GlobalKey navigationRailKey = GlobalKey();
  Size? navigationRailSize;
  double? progress;

  bool connected = false;
  bool busy = false;
  String? lastError;

  FirmwareVersion? firmwareVersion;
  BatteryCharge? battery;
  Set<int> capabilities = <int>{};

  int activeSlot = 0;
  List<SlotTypes> slotTypes = List<SlotTypes>.generate(8, (_) => SlotTypes());
  List<EnabledSlotInfo> enabledSlots =
      List<EnabledSlotInfo>.generate(8, (_) => EnabledSlotInfo());
  List<String> hfNames = List<String>.filled(8, '');
  List<String> lfNames = List<String>.filled(8, '');
  PollingConfiguration polling = PollingConfiguration();
  PollingRuntimeStatus? pollingStatus;

  Timer? _refreshTimer;

  bool get supports16Slots =>
      capabilities.contains(ChameleonCommand.getSlotInfoV2.value);
  bool get supportsPolling =>
      capabilities.contains(ChameleonCommand.getPollingConfig.value);

  int get slotCount => supports16Slots ? 16 : 8;

  Future<bool> connectDevice(Chameleon device) async {
    final c = connector;
    if (c == null) return false;
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      final ok = await c.connectSpecificDevice(device.port);
      if (!ok) {
        lastError = 'Connection rejected';
        return false;
      }
      communicator = ChameleonCommunicator(log ?? Logger(), port: c);
      connected = true;
      await refreshAll();
      _startRefreshTimer();
      return true;
    } catch (e) {
      lastError = e.toString();
      connected = false;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshAll() async {
    final comm = communicator;
    if (comm == null) return;
    try {
      capabilities = (await comm.getDeviceCapabilities()).toSet();
      if (supports16Slots) {
        slotTypes = await comm.getSlotTagTypesV2();
        enabledSlots = await comm.getEnabledSlotsV2();
        hfNames = List<String>.filled(16, '');
        lfNames = List<String>.filled(16, '');
      } else {
        slotTypes = await comm.getSlotTagTypes();
        enabledSlots = await comm.getEnabledSlots();
        hfNames = List<String>.filled(8, '');
        lfNames = List<String>.filled(8, '');
      }
      activeSlot = await comm.getActiveSlot();
      battery = await comm.getBatteryCharge();
      firmwareVersion = await comm.getFirmwareVersion();
      for (var i = 0; i < slotTypes.length; i++) {
        try {
          hfNames[i] = await comm.getSlotTagName(i, TagFrequency.hf);
        } catch (_) {}
        try {
          lfNames[i] = await comm.getSlotTagName(i, TagFrequency.lf);
        } catch (_) {}
      }
      if (supportsPolling) {
        polling = await comm.getPollingConfig();
        pollingStatus = await comm.getPollingStatus();
      }
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    }
    notifyListeners();
  }

  Future<void> refreshPollingStatus() async {
    if (communicator == null || !supportsPolling) return;
    try {
      pollingStatus = await communicator!.getPollingStatus();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> activateSlot(int slot) async {
    if (communicator == null) return;
    await communicator!.activateSlot(slot);
    activeSlot = slot;
    notifyListeners();
  }

  Future<void> setSlotEnabled(
      int slot, TagFrequency frequency, bool enabled) async {
    if (communicator == null) return;
    await communicator!.enableSlot(slot, frequency, enabled);
    if (slot < enabledSlots.length) {
      if (frequency == TagFrequency.hf) {
        enabledSlots[slot].hf = enabled;
      } else if (frequency == TagFrequency.lf) {
        enabledSlots[slot].lf = enabled;
      }
    }
    notifyListeners();
  }

  Future<void> setSlotName(
      int slot, TagFrequency frequency, String name) async {
    if (communicator == null) return;
    await communicator!.setSlotTagName(slot, name, frequency);
    if (frequency == TagFrequency.hf && slot < hfNames.length) {
      hfNames[slot] = name;
    } else if (frequency == TagFrequency.lf && slot < lfNames.length) {
      lfNames[slot] = name;
    }
    notifyListeners();
  }

  Future<void> applyPolling(PollingConfiguration config) async {
    if (communicator == null) return;
    await communicator!.setPollingConfig(config);
    polling = config;
    await refreshPollingStatus();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!connected) return;
      refreshPollingStatus();
    });
  }

  void onConnectorStateChanged() {
    connected = connector?.connected ?? false;
    if (!connected) {
      communicator = null;
      progress = null;
      _refreshTimer?.cancel();
    }
    notifyListeners();
  }

  bool isAutoReconnectSuppressed(dynamic devicePort) => false;

  void clearAutoReconnectSuppression([dynamic devicePort]) {}

  void syncAutoReconnectSuppression(Iterable<dynamic> visiblePorts) {}

  Future<void> disconnect({bool manual = false}) async {
    _refreshTimer?.cancel();
    await connector?.performDisconnect();
    communicator = null;
    connected = false;
    progress = null;
    notifyListeners();
  }

  void changesMade() {
    notifyListeners();
  }

  void setProgressBar(dynamic value) {
    progress = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}



