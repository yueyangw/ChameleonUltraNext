import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final TextEditingController _apduController =
      TextEditingController(text: '00 A4 04 00 00');
  String? _output;
  String? _error;
  bool _busy = false;

  Future<void> _emvScan() async {
    final comm = context.read<ChameleonGUIState>().communicator;
    if (comm == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await comm.hf14a4EmvScan();
      setState(() => _output = bytesToHexSpace(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendApdu() async {
    final comm = context.read<ChameleonGUIState>().communicator;
    if (comm == null) return;
    final text = _apduController.text.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(text) || text.length.isOdd) {
      setState(() => _error = 'APDU 必须是完整的十六进制字节');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _output = null;
    });
    try {
      final data = await comm.hf14a4ReaderApdu(hexToBytes(text));
      setState(() => _output = bytesToHexSpace(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('高级诊断')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.credit_card),
                  title: Text('EMV / ISO14443-4'),
                  subtitle: Text('扫描并读取 EMV 应用信息'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _emvScan,
                      icon: const Icon(Icons.search),
                      label: const Text('执行 EMV 扫描'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apduController,
            decoration: const InputDecoration(
              labelText: 'APDU (hex)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _sendApdu,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: const Text('发送 APDU'),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
              ),
            ),
          if (_output != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  _output!,
                  style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
