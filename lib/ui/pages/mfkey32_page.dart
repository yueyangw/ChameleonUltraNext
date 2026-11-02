import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/recovery/recovery.dart' as recovery;
import 'package:chameleon_ultra_next/recovery/recovery.dart' show Mfkey32Dart;

class Mfkey32Page extends StatefulWidget {
  const Mfkey32Page({super.key});

  @override
  State<Mfkey32Page> createState() => _Mfkey32PageState();
}

class _Mfkey32PageState extends State<Mfkey32Page> {
  bool _loading = false;
  bool _detectionMode = false;
  int _count = 0;
  String? _error;
  final List<String> _recovered = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final comm = context.read<ChameleonGUIState>().communicator;
    if (comm == null) return;
    try {
      final mode = await comm.isMf1DetectionMode();
      final count = await comm.getMf1DetectionCount();
      if (!mounted) return;
      setState(() {
        _detectionMode = mode;
        _count = count;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _toggleDetection() async {
    final comm = context.read<ChameleonGUIState>().communicator;
    if (comm == null) return;
    try {
      await comm.setMf1DetectionStatus(!_detectionMode);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _recover() async {
    final comm = context.read<ChameleonGUIState>().communicator;
    if (comm == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _recovered.clear();
    });
    try {
      final detections = await comm.getMf1DetectionResult(_count);
      for (final uidEntry in detections.entries) {
        for (final blockEntry in uidEntry.value.entries) {
          for (final typeEntry in blockEntry.value.entries) {
            final values = typeEntry.value;
            for (var i = 0; i < values.length; i++) {
              for (var j = i + 1; j < values.length; j++) {
                final mfkey = Mfkey32Dart(
                  uid: uidEntry.key,
                  nt0: values[i].nt,
                  nt1: values[j].nt,
                  nr0Enc: values[i].nr,
                  ar0Enc: values[i].ar,
                  nr1Enc: values[j].nr,
                  ar1Enc: values[j].ar,
                );
                final key = await recovery.mfkey32(mfkey);
                final text = key
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join()
                    .toUpperCase();
                setState(() {
                  _recovered.add(
                      'UID ${uidEntry.key.toRadixString(16).toUpperCase()} · '
                      '块 ${blockEntry.key} · ${typeEntry.key} · $text');
                });
              }
            }
          }
        }
      }
      if (_recovered.isEmpty) {
        setState(() => _error = '没有可恢复的 nonce 组');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MFKey32')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('检测模式'),
              subtitle: Text(_detectionMode ? '已启用，正在记录 nonce' : '未启用'),
              value: _detectionMode,
              onChanged: (value) async {
                await _toggleDetection();
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('已记录 nonce'),
              subtitle: Text('$_count 组'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refresh,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading || _count == 0 ? null : _recover,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.key),
            label: Text(_loading ? '计算中...' : '计算密钥'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
              ),
            ),
          ],
          if (_recovered.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('恢复结果', style: Theme.of(context).textTheme.titleMedium),
            for (final item in _recovered)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: SelectableText(item),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
