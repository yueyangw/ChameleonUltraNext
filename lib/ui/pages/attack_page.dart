import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/generated/i18n/app_localizations.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/recovery.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';

class AttackPage extends StatefulWidget {
  const AttackPage({super.key});

  @override
  State<AttackPage> createState() => _AttackPageState();
}

class _AttackPageState extends State<AttackPage> {
  late final MifareClassicRecovery _recovery;
  final List<String> _log = <String>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<ChameleonGUIState>();
    _recovery = MifareClassicRecovery(
      appState: state,
      update: () {
        if (mounted) setState(() {});
      },
      localizations: AppLocalizations.of(context)!,
      dictionaries: context.read<SharedPreferencesProvider>().getDictionaries(),
    );
    _recovery.selectedDictionary = Dictionary(
      name: 'Default',
      keys: gMifareClassicKeys,
      keyLength: 12,
    );
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _log.insert(0, '$label ...');
    });
    try {
      await action();
      setState(() => _log.insert(0, '$label: 完成'));
    } catch (e) {
      setState(() => _log.insert(0, '$label: 失败 $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('MIFARE Classic 密钥恢复')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('当前操作', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_recovery.state.isEmpty ? '空闲' : _recovery.state),
                  if (_recovery.error.isNotEmpty)
                    Text(_recovery.error,
                        style: TextStyle(color: theme.colorScheme.error)),
                  if (_recovery.hardnestedProgress != null)
                    LinearProgressIndicator(
                        value: _recovery.hardnestedProgress),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run('读取卡片信息',
                                () async => _recovery.initialize()),
                        icon: const Icon(Icons.memory),
                        label: const Text('读取卡片'),
                      ),
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run('检测密钥',
                                () => _recovery.checkKeys()),
                        icon: const Icon(Icons.key),
                        label: const Text('字典检测'),
                      ),
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run('自动恢复密钥',
                                () => _recovery.recoverKeys()),
                        icon: const Icon(Icons.lock_open),
                        label: const Text('自动恢复'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('扇区状态', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (var sector = 0; sector < 16; sector++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: <Widget>[
                          SizedBox(width: 60, child: Text('扇区 $sector')),
                          Text(
                            'A: ${_keyText(sector, 0)}  B: ${_keyText(sector, 1)}',
                            style: const TextStyle(fontFamily: 'RobotoMono'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('日志', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final line in _log) Text(line),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _keyText(int sector, int keyType) {
    final key = _recovery.validKeys[sector + keyType * 40];
    return key.isEmpty ? '未找到' : bytesToHex(key).toUpperCase();
  }
}
