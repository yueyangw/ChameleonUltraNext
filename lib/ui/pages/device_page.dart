import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/bridge/chameleon.dart';
import 'package:chameleon_ultra_next/connector/serial_abstract.dart';

/// Device screen: scan for, connect to and disconnect from a Chameleon Ultra/Lite.
class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  List<Chameleon> _devices = const <Chameleon>[];
  bool _busy = false;
  String? _error;

  Future<void> _scan() async {
    final connector = context.read<ChameleonGUIState>().connector;
    if (connector == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final devices = await connector.availableChameleons(false);
      if (!mounted) return;
      setState(() => _devices = devices);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(Chameleon device) async {
    final appState = context.read<ChameleonGUIState>();
    final connector = appState.connector;
    if (connector == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final ok = await connector.connectSpecificDevice(device.port);
      if (!ok) {
        throw StateError('Connection to the device was rejected.');
      }
      final log = appState.log ?? Logger();
      appState.communicator = ChameleonCommunicator(log, port: connector);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final appState = context.read<ChameleonGUIState>();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await appState.disconnect();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connector = context.watch<ChameleonGUIState>().connector;
    final connected = connector?.connected ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chameleon Ultra'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: Icon(
                connected ? Icons.link : Icons.link_off,
                color: connected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              title: Text(connected ? 'Connected' : 'Not connected'),
              subtitle: Text(
                connected
                    ? (connector?.portName ?? 'unknown port')
                    : 'Select a device below to connect.',
              ),
              trailing: connected
                  ? TextButton(
                      onPressed: _busy ? null : _disconnect,
                      child: const Text('Disconnect'),
                    )
                  : null,
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.onErrorContainer,
                ),
                title: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text('Available devices', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No devices found yet. Tap refresh to scan.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            )
          else
            for (final device in _devices)
              Card(
                child: ListTile(
                  leading: Icon(
                    device.type == ConnectionType.ble
                        ? Icons.bluetooth
                        : Icons.usb,
                  ),
                  title: Text(device.device.name),
                  subtitle: Text('${device.type.name} • ${device.port}'),
                  onTap: _busy ? null : () => _connect(device),
                ),
              ),
        ],
      ),
    );
  }
}
