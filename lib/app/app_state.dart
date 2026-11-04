import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'package:chameleon_ultra_next/bridge/chameleon.dart';
import 'package:chameleon_ultra_next/connector/serial_abstract.dart';
import 'package:chameleon_ultra_next/core/models/slot_info.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';

/// Features of this client that the connected firmware cannot serve.
enum FirmwareIssue {
  noSixteenSlots('不支持 16 卡槽（仅 8 个卡槽可用）'),
  noPolling('不支持卡槽轮询'),
  noReaderAwarePolling('轮询是旧版计时引擎，请升级固件获得按读卡器行为换卡的新引擎');

  const FirmwareIssue(this.message);
  final String message;
}

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
  List<EnabledSlotInfo> enabledSlots = List<EnabledSlotInfo>.generate(
    8,
    (_) => EnabledSlotInfo(),
  );
  List<String> hfNames = List<String>.filled(8, '');
  List<String> lfNames = List<String>.filled(8, '');
  PollingConfiguration polling = PollingConfiguration();
  PollingRuntimeStatus? pollingStatus;

  Timer? _refreshTimer;
  int _pauseDepth = 0;
  bool _polling = false;
  bool _capabilitiesLoaded = false;

  /// Set once the "firmware too old" dialog was shown for this connection.
  bool firmwareHintShown = false;

  bool get supports16Slots =>
      capabilities.contains(ChameleonCommand.getSlotInfoV2.value);
  bool get supportsPolling =>
      capabilities.contains(ChameleonCommand.getPollingConfig.value);

  int get slotCount => supports16Slots ? 16 : 8;

  /// Features of this client the connected firmware does not provide. Empty
  /// while disconnected or until the first refresh finished.
  List<FirmwareIssue> get firmwareIssues {
    if (!connected || !_capabilitiesLoaded) return const <FirmwareIssue>[];
    return <FirmwareIssue>[
      if (!supports16Slots) FirmwareIssue.noSixteenSlots,
      if (!supportsPolling)
        FirmwareIssue.noPolling
      else if (!polling.supportsReaderAware)
        FirmwareIssue.noReaderAwarePolling,
    ];
  }

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
    _pauseDepth++;
    try {
      final caps = (await comm.getDeviceCapabilities()).toSet();
      var types = <SlotTypes>[];
      var enabled = <EnabledSlotInfo>[];
      var useV2 = caps.contains(ChameleonCommand.getSlotInfoV2.value);
      if (useV2) {
        try {
          types = await comm.getSlotTagTypesV2();
          enabled = await comm.getEnabledSlotsV2();
        } catch (_) {
          // Fall back to the 8-slot commands every firmware understands.
          useV2 = false;
        }
      }
      if (!useV2) {
        types = await comm.getSlotTagTypes();
        enabled = await comm.getEnabledSlots();
      }
      final count = types.length < enabled.length
          ? types.length
          : enabled.length;
      types = types.sublist(0, count);
      enabled = enabled.sublist(0, count);

      // Independent commands (different command ids) are issued together so
      // their BLE round trips overlap instead of adding up.
      final pollingFuture =
          caps.contains(ChameleonCommand.getPollingConfig.value)
          ? Future.wait<Object>(<Future<Object>>[
              comm.getPollingConfig(),
              comm.getPollingStatus(),
            ])
          : null;
      final results = await Future.wait<Object>(<Future<Object>>[
        comm.getActiveSlot(),
        comm.getBatteryCharge(),
        comm.getFirmwareVersion(),
      ]);
      final active = results[0] as int;
      final batt = results[1] as BatteryCharge;
      final fw = results[2] as FirmwareVersion;
      PollingConfiguration? pollingConfig;
      PollingRuntimeStatus? pollingState;
      if (pollingFuture != null) {
        final p = await pollingFuture;
        pollingConfig = p[0] as PollingConfiguration;
        pollingState = p[1] as PollingRuntimeStatus;
      }

      // Commit everything at once so the UI never sees mixed slot counts.
      // Names are loaded afterwards in the background (up to 32 requests).
      capabilities = caps;
      slotTypes = types;
      enabledSlots = enabled;
      if (hfNames.length != count) hfNames = List<String>.filled(count, '');
      if (lfNames.length != count) lfNames = List<String>.filled(count, '');
      activeSlot = active;
      battery = batt;
      firmwareVersion = fw;
      if (pollingConfig != null) polling = pollingConfig;
      pollingStatus = pollingState;
      lastError = null;
      _loadNamesInBackground(comm, count);
    } catch (e) {
      lastError = e.toString();
    } finally {
      _pauseDepth--;
      _capabilitiesLoaded = true;
    }
    notifyListeners();
  }

  int _nameLoadGeneration = 0;

  /// Reads slot nicknames one by one without blocking the connection flow.
  void _loadNamesInBackground(ChameleonCommunicator comm, int count) {
    final generation = ++_nameLoadGeneration;
    Future<void>(() async {
      bool stale() =>
          generation != _nameLoadGeneration ||
          !connected ||
          !identical(communicator, comm);
      for (var i = 0; i < count; i++) {
        if (stale()) return;
        var changed = false;
        try {
          final name = await comm.getSlotTagName(i, TagFrequency.hf);
          if (stale()) return;
          if (i < hfNames.length && hfNames[i] != name) {
            hfNames[i] = name;
            changed = true;
          }
        } catch (_) {}
        try {
          final name = await comm.getSlotTagName(i, TagFrequency.lf);
          if (stale()) return;
          if (i < lfNames.length && lfNames[i] != name) {
            lfNames[i] = name;
            changed = true;
          }
        } catch (_) {}
        if (changed) notifyListeners();
      }
    });
  }

  Future<void> refreshPollingStatus() async {
    if (communicator == null || !supportsPolling) return;
    try {
      pollingStatus = await communicator!.getPollingStatus();
      notifyListeners();
    } catch (_) {}
  }

  /// Suspends the periodic status poll while a long operation (sniffing,
  /// dumping, writing) owns the serial link. Calls nest.
  void pauseRefresh() => _pauseDepth++;

  void resumeRefresh() {
    if (_pauseDepth > 0) _pauseDepth--;
  }

  Future<void> activateSlot(int slot) async {
    if (communicator == null) return;
    await communicator!.activateSlot(slot);
    activeSlot = slot;
    notifyListeners();
  }

  Future<void> setSlotEnabled(
    int slot,
    TagFrequency frequency,
    bool enabled,
  ) async {
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
    int slot,
    TagFrequency frequency,
    String name,
  ) async {
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
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!connected || _pauseDepth > 0 || _polling) return;
      _polling = true;
      try {
        await refreshPollingStatus();
      } finally {
        _polling = false;
      }
    });
  }

  void onConnectorStateChanged() {
    connected = connector?.connected ?? false;
    if (!connected) {
      _resetDeviceState();
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
    connected = false;
    _resetDeviceState();
    notifyListeners();
  }

  void _resetDeviceState() {
    _nameLoadGeneration++;
    communicator = null;
    progress = null;
    _pauseDepth = 0;
    _polling = false;
    _capabilitiesLoaded = false;
    firmwareHintShown = false;
    capabilities = <int>{};
    pollingStatus = null;
    slotTypes = List<SlotTypes>.generate(8, (_) => SlotTypes());
    enabledSlots = List<EnabledSlotInfo>.generate(8, (_) => EnabledSlotInfo());
    hfNames = List<String>.filled(8, '');
    lfNames = List<String>.filled(8, '');
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
