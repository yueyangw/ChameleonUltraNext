import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/helpers/lf_sniff.dart';

class LfSniffPage extends StatefulWidget {
  const LfSniffPage({super.key});

  @override
  State<LfSniffPage> createState() => _LfSniffPageState();
}

class _LfSniffPageState extends State<LfSniffPage> {
  bool _capturing = false;
  int _timeoutMs = 2000;
  LfSniffCapture? _capture;
  String? _error;

  Future<void> _captureSamples() async {
    final comm = context.read<ChameleonGUIState>().communicator;
    if (comm == null) {
      setState(() => _error = '未连接设备');
      return;
    }
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final samples = await comm.lfSniff(timeoutMs: _timeoutMs);
      setState(() => _capture = LfSniffCapture.fromSamples(samples));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _exportSamples() async {
    final capture = _capture;
    if (capture == null) return;
    await FilePicker.saveFile(
      fileName:
          'lf-sniff-${DateTime.now().toIso8601String().replaceAll(':', '-')}.bin',
      bytes: capture.samples,
    );
  }

  Future<void> _importSamples() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    if (bytes == null) return;
    setState(() {
      _capture = LfSniffCapture.fromSamples(bytes);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final capture = _capture;
    final summary = capture?.summary;
    final modulation = capture?.modulation;
    final decode = capture == null
        ? null
        : decodeLfManchester(capture.samples, clockDivisor: 64);
    return Scaffold(
      appBar: AppBar(
        title: const Text('LF 嗅探'),
        actions: [
          IconButton(
            tooltip: '导入采样',
            onPressed: _importSamples,
            icon: const Icon(Icons.file_open),
          ),
          IconButton(
            tooltip: '导出采样',
            onPressed: capture == null ? null : _exportSamples,
            icon: const Icon(Icons.save_alt),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _capturing ? null : _captureSamples,
        icon: _capturing
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.graphic_eq),
        label: Text(_capturing ? '嗅探中...' : '开始嗅探'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('采样时长', style: Theme.of(context).textTheme.titleMedium),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          min: 500,
                          max: 10000,
                          divisions: 19,
                          value: _timeoutMs.toDouble(),
                          label: '$_timeoutMs ms',
                          onChanged: _capturing
                              ? null
                              : (value) =>
                                  setState(() => _timeoutMs = value.round()),
                        ),
                      ),
                      Text('$_timeoutMs ms'),
                    ],
                  ),
                ],
              ),
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
          if (summary != null) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('摘要', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _kv('样本数', '${summary.sampleCount}'),
                    _kv('时长', '${summary.durationMs.toStringAsFixed(1)} ms'),
                    _kv('最小值', '${summary.min}'),
                    _kv('最大值', '${summary.max}'),
                    _kv('平均值', '${summary.mean}'),
                    _kv('动态范围', '${summary.dynamicRange}'),
                    _kv('间隙数', '${summary.gapCount}'),
                    if (modulation != null) ...[
                      const Divider(),
                      _kv('调制', modulation.label),
                      if (modulation.nearestClockDivisor != null)
                        _kv('时钟分频', '${modulation.nearestClockDivisor}'),
                      if (modulation.halfPeriodUs != null)
                        _kv('半周期', '${modulation.halfPeriodUs} µs'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (decode != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Manchester 解码 (RF/64)',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        SelectableText(
                          decode.hexString.isEmpty ? '无有效数据' : decode.hexString,
                          style: const TextStyle(fontFamily: 'RobotoMono'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
                width: 100,
                child: Text(key, style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );
}
