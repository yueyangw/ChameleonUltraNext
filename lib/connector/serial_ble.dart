import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chameleon_ultra_next/connector/serial_abstract.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

// Regular
Uuid nrfUUID = Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
Uuid uartRX = Uuid.parse("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
Uuid uartTX = Uuid.parse("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

// DFU
Uuid dfuUUID = Uuid.parse("FE59");
Uuid dfuControl = Uuid.parse("8EC90001-F315-4F60-9FB8-838830DAEA50");
Uuid dfuFirmware = Uuid.parse("8EC90002-F315-4F60-9FB8-838830DAEA50");

class BLESerial extends AbstractSerial {
  FlutterReactiveBle flutterReactiveBle = FlutterReactiveBle();
  QualifiedCharacteristic? txCharacteristic;
  QualifiedCharacteristic? rxCharacteristic;
  QualifiedCharacteristic? firmwareCharacteristic;
  Stream<List<int>>? receivedDataStream;
  StreamSubscription<ConnectionStateUpdate>? connection;
  Map<String, Chameleon> chameleonMap = {};
  bool inSearch = false;

  BLESerial({required super.log});

  Future<List> availableDevices() async {
    if (inSearch) {
      log.w("Multiple searches in one time not allowed! FIXME");
      return [];
    }

    List<DiscoveredDevice> foundDevices = [];
    await performDisconnect();

    Completer<List<DiscoveredDevice>> completer =
        Completer<List<DiscoveredDevice>>();
    late StreamSubscription<DiscoveredDevice> subscription;

    inSearch = true;
    Timer? hardTimer;
    Timer? graceTimer;

    void finish() {
      hardTimer?.cancel();
      graceTimer?.cancel();
      subscription.cancel();
      inSearch = false;
      if (!completer.isCompleted) {
        completer.complete(foundDevices);
        log.d('Found BLE devices: ${foundDevices.length}');
      }
    }

    bool isChameleonName(String name) =>
        name.startsWith('ChameleonUltra') ||
        name.startsWith('ChameleonLite') ||
        name.startsWith('CU-') ||
        name.startsWith('CL-');

    subscription = flutterReactiveBle
        .scanForDevices(
          withServices: [nrfUUID, dfuUUID],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          (device) {
            for (var foundDevice in foundDevices) {
              if (foundDevice.id == device.id) {
                // Keep the entry that carries a name (scan response may arrive later).
                if (foundDevice.name.isEmpty && device.name.isNotEmpty) {
                  foundDevices[foundDevices.indexOf(foundDevice)] = device;
                } else {
                  return;
                }
                break;
              }
            }
            if (!foundDevices.any((d) => d.id == device.id)) {
              foundDevices.add(device);
            }
            // A Chameleon was found: don't wait for the full window, just give
            // other nearby devices a short grace period to show up.
            if (isChameleonName(device.name) && graceTimer == null) {
              graceTimer = Timer(const Duration(milliseconds: 600), finish);
            }
          },
          onError: (e) {
            log.e("Got BLE search error: $e");
            hardTimer?.cancel();
            graceTimer?.cancel();
            inSearch = false;
            if (Platform.isIOS) {
              if (!completer.isCompleted) completer.completeError(e);
            } else if (!completer.isCompleted) {
              completer.complete([]); // Other platforms: we don't care
            }
          },
        );

    hardTimer = Timer(const Duration(seconds: 2), finish);

    return completer.future;
  }

  @override
  bool isManualConnectionSupported() {
    return false;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    List<Chameleon> output = [];
    for (var bleDevice in await availableDevices()) {
      var dfuMode = false;
      if (bleDevice.name.startsWith('ChameleonUltra')) {
        device = ChameleonDevice.ultra;
      } else if (bleDevice.name.startsWith('ChameleonLite')) {
        device = ChameleonDevice.lite;
      } else if (bleDevice.name.startsWith('CU-')) {
        device = ChameleonDevice.ultra;
        dfuMode = true;
      } else if (bleDevice.name.startsWith('CL-')) {
        device = ChameleonDevice.lite;
        dfuMode = true;
      } else {
        // regular nRF device with UART
        continue;
      }

      connectionType = ConnectionType.ble;

      log.d("Found Chameleon ${chameleonDeviceName(device)}!");
      if (!onlyDFU || onlyDFU && dfuMode) {
        output.add(
          Chameleon(
            port: bleDevice.id,
            device: device,
            type: connectionType,
            dfu: dfuMode,
          ),
        );
      }

      chameleonMap[bleDevice.id] = Chameleon(
        port: bleDevice.id,
        device: device,
        type: connectionType,
        dfu: dfuMode,
      );
    }

    return output;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    // As BLE is unstable, we try to connect 5 times
    // And fail only then. The first attempt connects directly (the device was
    // just seen by the scan); retries fall back to prescan-based connecting.
    bool ret = false;
    for (var i = 0; i < 5; i++) {
      ret = await connectSpecificInternal(devicePort, direct: i == 0);
      if (ret) {
        break;
      }
    }

    return ret;
  }

  Future<bool> connectSpecificInternal(
    dynamic devicePort, {
    bool direct = false,
  }) async {
    Completer<bool> completer = Completer<bool>();
    List<Uuid> services = [nrfUUID, uartRX, uartTX];
    if (chameleonMap[devicePort]!.dfu) {
      services = [dfuUUID, dfuControl, dfuFirmware];
    }

    await performDisconnect();
    pendingConnection = true;
    final isDfuDevice = chameleonMap[devicePort]!.dfu;
    final Stream<ConnectionStateUpdate> connectionStream = direct
        ? flutterReactiveBle.connectToDevice(
            id: devicePort,
            servicesWithCharacteristicsToDiscover: isDfuDevice
                ? {
                    dfuUUID: [dfuControl, dfuFirmware],
                  }
                : {
                    nrfUUID: [uartRX, uartTX],
                  },
            connectionTimeout: const Duration(seconds: 6),
          )
        : flutterReactiveBle.connectToAdvertisingDevice(
            id: devicePort,
            withServices: services,
            prescanDuration: const Duration(seconds: 5),
          );
    connection = connectionStream.listen(
      (connectionState) async {
        log.w(connectionState);
        if (connectionState.connectionState ==
            DeviceConnectionState.connected) {
          if (chameleonMap[devicePort]!.dfu) {
            connected = true;
            pendingConnection = false;
            txCharacteristic = QualifiedCharacteristic(
              serviceId: dfuUUID,
              characteristicId: dfuControl,
              deviceId: connectionState.deviceId,
            );
            receivedDataStream = flutterReactiveBle.subscribeToCharacteristic(
              txCharacteristic!,
            );
            receivedDataStream!.listen(
              (data) async {
                if (messageCallback != null) {
                  try {
                    await messageCallback(Uint8List.fromList(data));
                  } catch (_) {
                    log.w(
                      "Received unexpected data: ${bytesToHex(Uint8List.fromList(data))}",
                    );
                  }
                }
              },
              onError: (dynamic error) async {
                await performDisconnect();
                log.e(error);
              },
            );

            rxCharacteristic = QualifiedCharacteristic(
              serviceId: dfuUUID,
              characteristicId: dfuControl,
              deviceId: connectionState.deviceId,
            );

            firmwareCharacteristic = QualifiedCharacteristic(
              serviceId: dfuUUID,
              characteristicId: dfuFirmware,
              deviceId: connectionState.deviceId,
            );

            portName = devicePort;
            device = chameleonMap[devicePort]!.device;
            activeDevicePort = devicePort;

            isDFU = true;
            completer.complete(true);
          } else {
            txCharacteristic = QualifiedCharacteristic(
              serviceId: nrfUUID,
              characteristicId: uartTX,
              deviceId: connectionState.deviceId,
            );
            receivedDataStream = flutterReactiveBle.subscribeToCharacteristic(
              txCharacteristic!,
            );
            receivedDataStream!.listen(
              (data) async {
                if (messageCallback != null) {
                  try {
                    await messageCallback(Uint8List.fromList(data));
                  } catch (_) {
                    log.w(
                      "Received unexpected data: ${bytesToHex(Uint8List.fromList(data))}",
                    );
                  }
                }
              },
              onError: (dynamic error) async {
                await performDisconnect();
                log.e(error);
              },
            );

            rxCharacteristic = QualifiedCharacteristic(
              serviceId: nrfUUID,
              characteristicId: uartRX,
              deviceId: connectionState.deviceId,
            );

            try {
              // Larger ATT MTU = fewer round trips for big payloads (dumps).
              try {
                await flutterReactiveBle
                    .requestMtu(deviceId: connectionState.deviceId, mtu: 247)
                    .timeout(const Duration(seconds: 2));
              } catch (_) {}
              await flutterReactiveBle.writeCharacteristicWithResponse(
                rxCharacteristic!,
                value: Uint8List.fromList([
                  0x11,
                  0xef,
                  0x03,
                  0xfb,
                  0x00,
                  0x00,
                  0x00,
                  0x00,
                  0x02,
                  0x00,
                ]),
              );

              connected = true;
              portName = devicePort;
              device = chameleonMap[devicePort]!.device;
              activeDevicePort = devicePort;

              connectionType = ConnectionType.ble;
              isDFU = false;

              completer.complete(true);
            } catch (_) {
              try {
                completer.complete(false);
              } catch (_) {}
            }
          }
        } else if (connectionState.connectionState ==
            DeviceConnectionState.disconnected) {
          await performDisconnect();
          try {
            completer.complete(false);
          } catch (_) {}
        }
      },
      onError: (Object error) {
        log.e(error);
        completer.complete(false);
      },
    );

    return completer.future;
  }

  @override
  Future<bool> performDisconnect() async {
    final hadState = hasConnectionState || connection != null;
    resetConnectionState();
    txCharacteristic = null;
    rxCharacteristic = null;
    firmwareCharacteristic = null;
    receivedDataStream = null;
    if (connection != null) {
      await connection!.cancel();
      connection = null;
      connected = false;
      if (hadState) {
        notifyConnectionStateChanged();
      }
      return true;
    }
    connected = false; // For debug button
    if (hadState) {
      notifyConnectionStateChanged();
    }
    return false;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    if (firmware) {
      await flutterReactiveBle.writeCharacteristicWithoutResponse(
        firmwareCharacteristic!,
        value: command,
      );
    } else {
      await flutterReactiveBle.writeCharacteristicWithResponse(
        rxCharacteristic!,
        value: command,
      );
    }

    return true;
  }
}
