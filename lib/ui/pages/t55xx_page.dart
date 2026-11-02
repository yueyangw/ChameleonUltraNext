import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';

class T55xxPage extends StatefulWidget {
  const T55xxPage({super.key});

  @override
  State<T55xxPage> createState() => _T55xxPageState();
}

class _T55xxPageState extends State<T55xxPage> {
  final TextEditingController _keyController =
      TextEditingController(text: '20206666');
  String? _dictionaryId;
  bool _running = false;
  int _index = 0;
  int _total = 0;
  String? _found;
  String? _error;
  final List<String> _tried = [];

  Future<void> _start() async {
    final state = context.read<ChameleonGUIState>();
    final comm = state.communicator;
    if (comm == null) {
      setState(() => _error = '未连接设备');
      return;
    }
    final dictionaries =
        state.sharedPreferencesProvider.getDictionaries(keyLength: 8);
    final dictionary = dictionaries.where((d) => d.id == _dictionaryId).firstOrNull;
    if (dictionary == null) {
      setState(() => _error = '请选择字典');
      return;
    }
    if (_keyController.text.trim().length != 8) {
      setState(() => _error = '新密码必须是 8 位十六进制字符');
      return;
    }
    setState(() {
      _running = true;
      _found = null;
      _error = null;
      _index = 0;
      _total = dictionary.keys.length;
      _tried.clear();
    });
    try {
      for (var i = 0; i < dictionary.keys.length; i++) {
        if (!_running) break;
        final key = dictionary.keys[i];
        setState(() {
          _index = i + 1;
          _tried.add(bytesToHexSpace(key));
        });
        try {
          await comm.writeEM410XtoT55XX(
            hexToBytes('DE AD BE EF FF'),
            hexToBytes(_keyController.text.trim()),
            [key],
          );
          final card = await comm.readEM410X();
          if (card != null && card.toString().toUpperCase().contains('DE AD BE EF FF')) {
            setState(() => _found = bytesToHexSpace(key));
            break;
          }
        } catch (_) {
          // Wrong password: continue with the next key.
        }
      }
      if (_found == null) {
        setState(() => _error = '字典中没有匹配的密码');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ChameleonGUIState>();
    final dictionaries =
        state.sharedPreferencesProvider.getDictionaries(keyLength: 8);
    return Scaffold(
      appBar: AppBar(title: const Text('T55xx 密码清理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: const ListTile(
              leading: Icon(Icons.warning_amber),
              title: Text('操作有风险'),
              subtitle: Text('该工具会尝试写入新的标签密码。请确认目标 T55xx 标签归你所有。'),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _dictionaryId,
            decoration: const InputDecoration(
              labelText: '密码字典',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final dictionary in dictionaries)
                DropdownMenuItem(
                  value: dictionary.id,
                  child: Text('${dictionary.name} (${dictionary.keys.length})'),
                ),
            ],
            onChanged: _running
                ? null
                : (value) => setState(() => _dictionaryId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            enabled: !_running,
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: '新密码 (4 字节 Hex)',
              border: OutlineInputBorder(),
              hintText: '20206666',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _running || _dictionaryId == null ? null : _start,
            icon: _running
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_open),
            label: Text(_running ? '尝试中...' : '开始'),
          ),
          const SizedBox(height: 16),
          if (_total > 0)
            LinearProgressIndicator(value: _total == 0 ? 0 : _index / _total),
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('进度: $_index / $_total'),
            ),
          if (_found != null)
            Card(
              color: Colors.green.withValues(alpha: 0.15),
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('找到密码'),
                subtitle: SelectableText(_found!),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _found!)),
                ),
              ),
            ),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('失败'),
                subtitle: Text(_error!),
              ),
            ),
          if (_tried.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('已尝试', style: Theme.of(context).textTheme.titleMedium),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final key in _tried) Chip(label: Text(key)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
