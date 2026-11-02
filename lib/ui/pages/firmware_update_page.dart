import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/helpers/flash.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';

class FirmwareUpdatePage extends StatefulWidget {
  const FirmwareUpdatePage({super.key});

  @override
  State<FirmwareUpdatePage> createState() => _FirmwareUpdatePageState();
}

class _FirmwareUpdatePageState extends State<FirmwareUpdatePage> {
  PlatformFile? _file;
  Uint8List? _zipBytes;
  Uint8List? _datBytes;
  Uint8List? _binBytes;
  String? _error;
  String _status = '请选择本地固件包（.zip）';
  bool _flashing = false;
  double _progress = 0;

  Future<void> _pickFirmware() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    setState(() {
      _file = file;
      _error = null;
      _status = '正在校验固件完整性...';
      _progress = 0;
    });
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final dat = archive.files
          .where((item) => item.name == 'application.dat')
          .cast<ArchiveFile?>()
          .firstOrNull;
      final bin = archive.files
          .where((item) => item.name == 'application.bin')
          .cast<ArchiveFile?>()
          .firstOrNull;
      final manifest = archive.files
          .where((item) => item.name == 'manifest.json')
          .cast<ArchiveFile?>()
          .firstOrNull;
      if (dat == null || bin == null || manifest == null) {
        throw const FormatException(
            '固件包缺少 manifest.json / application.dat / application.bin');
      }
      validateFiles(
        Uint8List.fromList(dat.content),
        Uint8List.fromList(bin.content),
      );
      setState(() {
        _zipBytes = Uint8List.fromList(bytes);
        _datBytes = Uint8List.fromList(dat.content);
        _binBytes = Uint8List.fromList(bin.content);
        _status = '校验通过 · ${(bytes.length / 1024).toStringAsFixed(1)} KiB';
      });
    } catch (e) {
      setState(() {
        _zipBytes = null;
        _datBytes = null;
        _binBytes = null;
        _error = e.toString();
        _status = '固件校验失败';
      });
    }
  }

  Future<void> _flash() async {
    final state = context.read<ChameleonGUIState>();
    final dat = _datBytes;
    final bin = _binBytes;
    if (dat == null || bin == null || _zipBytes == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认刷写固件'),
        content: Text(
          '将刷写 ${_file?.name ?? '固件包'}。\n\n'
          '刷写期间请保持 USB 连接，不要断电或拔线。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始刷写'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _flashing = true;
      _error = null;
      _status = '正在刷写，请勿断开设备...';
      _progress = 0;
    });
    try {
      await flashFile(
        state.communicator,
        state,
        dat,
        bin,
        (value) {
          if (mounted) setState(() => _progress = (value / 100).clamp(0, 1));
        },
        firmwareZip: _zipBytes!.toList(),
        enterDFU: true,
        scaffoldMessenger: ScaffoldMessenger.of(context),
      );
      if (!mounted) return;
      setState(() {
        _status = '刷写完成，设备正在重启';
        _progress = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _status = '刷写失败';
      });
    } finally {
      if (mounted) setState(() => _flashing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ChameleonGUIState>();
    return Scaffold(
      appBar: AppBar(title: const Text('固件升级')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.usb),
              title: const Text('当前设备'),
              subtitle: Text(state.connected
                  ? '${state.connector?.device.name} · ${state.connector?.portName}'
                  : '未连接设备'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: const ListTile(
              leading: Icon(Icons.warning_amber),
              title: Text('刷写风险'),
              subtitle: Text(
                '刷写期间请勿断开 USB/蓝牙。错误固件可能导致设备无法启动，请确认文件来源。',
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _flashing ? null : _pickFirmware,
            icon: const Icon(Icons.folder_open),
            label: Text(_file == null ? '选择本地固件包 (.zip)' : '重新选择固件包'),
          ),
          const SizedBox(height: 8),
          if (_file != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.archive),
                title: Text(_file!.name),
                subtitle: Text(_status),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_status),
              ),
            ),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('错误'),
                subtitle: Text(_error!),
              ),
            ),
          if (_flashing) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text('${(_progress * 100).round()}%'),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: (_flashing || _datBytes == null || !state.connected)
                ? null
                : _flash,
            icon: const Icon(Icons.system_update),
            label: const Text('开始刷写'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: state.connected && !_flashing
                ? () async {
                    await state.communicator?.enterDFUMode();
                  }
                : null,
            icon: const Icon(Icons.memory),
            label: const Text('仅进入 DFU'),
          ),
        ],
      ),
    );
  }

  List<int> _decodeHexString(String value) {
    final clean = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (clean.length.isOdd) {
      throw const FormatException('Invalid hash encoding');
    }
    return List<int>.generate(
      clean.length ~/ 2,
      (i) => int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16),
    );
  }
}
