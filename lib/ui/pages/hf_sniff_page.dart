import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/helpers/hf_sniff.dart';

class HfSniffPage extends StatefulWidget {
  const HfSniffPage({super.key});

  @override
  State<HfSniffPage> createState() => _HfSniffPageState();
}

class _HfSniffPageState extends State<HfSniffPage> {
  bool _capturing = false;
  HfSniffCapture? _capture;
  String? _error;
  String _status = '未开始';

  Future<void> _captureFrames() async {
    final state = context.read<ChameleonGUIState>();
    final comm = state.communicator;
    if (comm == null) {
      setState(() => _error = '未连接设备');
      return;
    }
    setState(() {
      _capturing = true;
      _error = null;
      _status = '正在嗅探 5 秒...';
    });
    try {
      final data = await comm.hf14aSniff(timeoutMs: 5000);
      if (data.isEmpty) {
        setState(() {
          _status = '未捕获到数据';
          _capture = null;
        });
        return;
      }
      final capture = HfSniffCapture.fromChameleonBytes(data);
      setState(() {
        _capture = capture;
        _status = '捕获完成：${capture.frames.length} 帧';
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _importTrace() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    if (bytes == null) return;
    try {
      final capture = HfSniffCapture.fromProxmarkTrace(bytes);
      setState(() {
        _capture = capture;
        _error = null;
        _status = '已载入 ${capture.frames.length} 帧';
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _exportTrace() async {
    final capture = _capture;
    if (capture == null) return;
    await FilePicker.saveFile(
      fileName:
          'hf-sniff-${DateTime.now().toIso8601String().replaceAll(':', '-')}.trace',
      bytes: capture.rawBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final capture = _capture;
    final summary = capture?.summary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('HF 嗅探'),
        actions: [
          IconButton(
            tooltip: '导入 trace',
            onPressed: _importTrace,
            icon: const Icon(Icons.file_open),
          ),
          IconButton(
            tooltip: '导出 trace',
            onPressed: capture == null ? null : _exportTrace,
            icon: const Icon(Icons.save_alt),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _capturing ? null : _captureFrames,
        icon: _capturing
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.radar),
        label: Text(_capturing ? '嗅探中...' : '开始嗅探'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(_status),
              subtitle: capture == null
                  ? null
                  : Text('原始数据 ${capture.rawBytes.length} 字节'),
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
            _SummaryCard(summary: summary),
            const SizedBox(height: 8),
            for (final annotated in capture!.annotatedFrames)
              Card(
                child: ListTile(
                  dense: true,
                  title: Text(annotated.label),
                  subtitle: SelectableText(annotated.frame.hexString),
                  trailing: IconButton(
                    tooltip: '复制',
                    icon: const Icon(Icons.copy),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: annotated.frame.hexString),
                    ),
                  ),
                ),
              ),
            if (capture.nonceGroups.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('可恢复的密钥组', style: Theme.of(context).textTheme.titleMedium),
              for (final group in capture.nonceGroups)
                Card(
                  child: ListTile(
                    title: Text('UID ${group.uid} · 块 ${group.block}'),
                    subtitle: Text(
                        '${group.keyType} · ${group.exchanges.length} 组 nonce${group.canRecover ? ' · 可计算' : ''}'),
                    trailing: TextButton(
                      onPressed: () {
                        final command = group.canRecover
                            ? buildMfkey32Command(group)
                            : buildMfkey64Command(group);
                        Clipboard.setData(ClipboardData(text: command));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制恢复命令')),
                        );
                      },
                      child: const Text('复制命令'),
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final HfSniffSummary summary;

  @override
  Widget build(BuildContext context) {
    final entries = <String, String>{
      '帧数': '${summary.frameCount}',
      '读卡器→卡': '${summary.readerFrameCount}',
      '卡→读卡器': '${summary.cardFrameCount}',
      if (summary.uid != null) 'UID': summary.uid!,
      if (summary.aids.isNotEmpty) 'AID': summary.aids.join(', '),
      if (summary.authRequests.isNotEmpty)
        '认证请求': summary.authRequests
            .map((item) => '${item.keyType}@${item.block}')
            .join(', '),
      if (summary.atcLabel != null) 'ATC': summary.atcLabel!,
      if (summary.amountMinorUnits != null)
        '金额': '${summary.amountMinorUnits! / 100}',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('摘要', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final entry in entries.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(entry.key,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                    Expanded(child: SelectableText(entry.value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
