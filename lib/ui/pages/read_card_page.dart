
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/generated/i18n/app_localizations.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/recovery.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';

/// Guided HF 14443A read: scan basic card info, try the default/custom
/// dictionary against every sector, fall back to the key-recovery attacks,
/// then read out whatever sectors are unlocked and save them to the wallet.
class ReadCardPage extends StatefulWidget {
  const ReadCardPage({super.key});

  @override
  State<ReadCardPage> createState() => _ReadCardPageState();
}

class _ReadCardPageState extends State<ReadCardPage> {
  bool _recoveryReady = false;
  MifareClassicRecovery? _recovery;

  CardData? _basicInfo;
  bool _scanning = false;
  bool _checking = false;
  bool _recovering = false;
  bool _dumping = false;
  String? _error;
  String _name = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppLocalizations can only be looked up once this widget is in the
    // tree, so the recovery helper is built here rather than in initState.
    if (_recoveryReady) return;
    _recoveryReady = true;
    final state = context.read<ChameleonGUIState>();
    _recovery = MifareClassicRecovery(
      appState: state,
      update: () {
        if (mounted) setState(() {});
      },
      localizations: AppLocalizations.of(context)!,
      dictionaries: context.read<SharedPreferencesProvider>().getDictionaries(),
    );
    _recovery!.selectedDictionary = Dictionary(
      name: 'Default',
      keys: gMifareClassicKeys,
      keyLength: 12,
    );
  }

  bool get _isClassic =>
      _basicInfo != null && _tagTypeForSak(_basicInfo!.sak) != null;

  static TagType? _tagTypeForSak(int sak) {
    switch (sak & 0xFF) {
      case 0x08:
        return TagType.mifare1K;
      case 0x18:
        return TagType.mifare4K;
      case 0x09:
        return TagType.mifareMini;
      case 0x19:
        return TagType.mifare2K;
      default:
        return null;
    }
  }

  Future<void> _scan() async {
    final state = context.read<ChameleonGUIState>();
    final comm = state.communicator;
    if (comm == null) {
      setState(() => _error = '未连接设备');
      return;
    }
    setState(() {
      _scanning = true;
      _error = null;
    });
    state.pauseRefresh();
    try {
      if (!await comm.isReaderDeviceMode()) {
        await comm.setReaderDeviceMode(true);
      }
      final info = await comm.scan14443aTag();
      if (!mounted) return;
      if (info == null) {
        setState(() => _error = '未检测到卡片，请将卡片贴近设备');
        return;
      }
      setState(() {
        _basicInfo = info;
        _name = 'Card ${bytesToHexSpace(info.uid).replaceAll(' ', '')}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '扫描失败：$e');
    } finally {
      state.resumeRefresh();
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _checkDictionary() async {
    final recovery = _recovery;
    if (recovery == null || _checking) return;
    final state = context.read<ChameleonGUIState>();
    setState(() {
      _checking = true;
      _error = null;
    });
    state.pauseRefresh();
    try {
      await recovery.initialize();
      await recovery.checkKeys();
    } catch (e) {
      if (mounted) setState(() => _error = '字典检测失败：$e');
    } finally {
      state.resumeRefresh();
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _recoverKeys() async {
    final recovery = _recovery;
    if (recovery == null || _recovering) return;
    final state = context.read<ChameleonGUIState>();
    setState(() {
      _recovering = true;
      _error = null;
    });
    state.pauseRefresh();
    try {
      await recovery.recoverKeys();
      if (recovery.error.isNotEmpty && mounted) {
        setState(() => _error = recovery.error);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '密钥恢复失败：$e');
    } finally {
      state.resumeRefresh();
      if (mounted) setState(() => _recovering = false);
    }
  }

  int get _foundSectorCount {
    final recovery = _recovery;
    if (recovery == null) return 0;
    var count = 0;
    final sectors = mfClassicGetSectorCount(recovery.mifareClassicType,
        isEV1: recovery.isMifareClassicEV1);
    for (var sector = 0; sector < sectors; sector++) {
      if (recovery.getSectorState(sector, 0) == ChameleonKeyCheckmark.found ||
          recovery.getSectorState(sector, 1) == ChameleonKeyCheckmark.found) {
        count++;
      }
    }
    return count;
  }

  int get _totalSectorCount {
    final recovery = _recovery;
    if (recovery == null) return 0;
    return mfClassicGetSectorCount(recovery.mifareClassicType,
        isEV1: recovery.isMifareClassicEV1);
  }

  Future<void> _saveToWallet() async {
    final recovery = _recovery;
    final info = _basicInfo;
    if (recovery == null || info == null) return;
    setState(() {
      _dumping = true;
      _error = null;
    });
    final state = context.read<ChameleonGUIState>();
    state.pauseRefresh();
    try {
      await recovery.dumpData();
      final tag =
          _tagTypeForSak(info.sak) ?? mfClassicGetChameleonTagType(
              recovery.mifareClassicType);
      final card = CardSave(
        uid: bytesToHexSpace(info.uid),
        name: _name.isEmpty ? 'Card ${bytesToHexSpace(info.uid)}' : _name,
        tag: tag,
        sak: info.sak,
        atqa: info.atqa,
        ats: info.ats,
        data: recovery.cardData,
      );
      if (!mounted) return;
      final prefs = context.read<SharedPreferencesProvider>();
      final cards = prefs.getCards()..add(card);
      prefs.setCards(cards);
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      messenger.showSnackBar(SnackBar(
          content:
              Text('已保存到卡包（$_foundSectorCount/$_totalSectorCount 个扇区有密钥）')));
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _error = '保存失败：$e');
    } finally {
      state.resumeRefresh();
      if (mounted) setState(() => _dumping = false);
    }
  }

  bool get _busy => _scanning || _checking || _recovering || _dumping;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _basicInfo;
    final recovery = _recovery;

    return Scaffold(
      appBar: AppBar(title: const Text('读取卡片')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!,
                    style:
                        TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ),
          const SizedBox(height: 8),

          // Step 1: basic info -------------------------------------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('1. 基本信息', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (info == null)
                    Text('贴近设备后点击扫描', style: theme.textTheme.bodySmall)
                  else ...[
                    SelectableText('UID: ${bytesToHexSpace(info.uid)}'),
                    Text(
                        'SAK: ${info.sak.toRadixString(16).padLeft(2, '0').toUpperCase()}'
                        '   ATQA: ${bytesToHexSpace(info.atqa)}'),
                    if (info.ats.isNotEmpty)
                      Text('ATS: ${bytesToHexSpace(info.ats)}'),
                    Text(_isClassic ? '类型: MIFARE Classic' : '类型: 非 MIFARE Classic（无法恢复密钥）'),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: '保存名称',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      controller: TextEditingController(text: _name)
                        ..selection =
                            TextSelection.collapsed(offset: _name.length),
                      onChanged: (v) => _name = v,
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: _scanning
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.nfc),
                    label: Text(info == null ? '扫描卡片' : '重新扫描'),
                  ),
                ],
              ),
            ),
          ),

          if (info != null && _isClassic) ...[
            const SizedBox(height: 12),
            // Step 2: dictionary ------------------------------------------------
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('2. 字典检测扇区密钥', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('用默认字典和已导入的字典尝试每个扇区的 Key A/B',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    if (recovery != null && recovery.state.isNotEmpty)
                      Text(recovery.state, style: theme.textTheme.bodySmall),
                    if (recovery?.keyCheckProgress != null)
                      LinearProgressIndicator(
                          value: recovery!.keyCheckProgress),
                    if (recovery != null && _totalSectorCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            '已找到 $_foundSectorCount / $_totalSectorCount 个扇区的密钥'),
                      ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _checkDictionary,
                      icon: _checking
                          ? const SizedBox.square(
                              dimension: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.key),
                      label: const Text('开始字典检测'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            // Step 3: algorithm recovery ----------------------------------------
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('3. 算法恢复剩余密钥', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('字典未命中时，依次尝试后门、darkside、nested、hardnested',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    if (recovery != null && recovery.state.isNotEmpty)
                      Text(recovery.state, style: theme.textTheme.bodySmall),
                    if (recovery?.hardnestedProgress != null)
                      LinearProgressIndicator(
                          value: recovery!.hardnestedProgress),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _recoverKeys,
                      icon: _recovering
                          ? const SizedBox.square(
                              dimension: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.lock_open),
                      label: const Text('开始算法恢复'),
                    ),
                  ],
                ),
              ),
            ),

            if (recovery != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('扇区密钥状态', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (var sector = 0; sector < _totalSectorCount; sector++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              SizedBox(width: 56, child: Text('扇区 $sector')),
                              Expanded(
                                child: Text(
                                  'A: ${_keyText(recovery, sector, 0)}   '
                                  'B: ${_keyText(recovery, sector, 1)}',
                                  style: const TextStyle(
                                      fontFamily: 'RobotoMono', fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || _foundSectorCount == 0
                    ? null
                    : _saveToWallet,
                icon: _dumping
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_alt),
                label: Text(_foundSectorCount == 0
                    ? '尚未找到任何密钥'
                    : '读取已知扇区并保存到卡包'),
              ),
            ),
          ] else if (info != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _saveIdentityOnly,
                icon: const Icon(Icons.save_alt),
                label: const Text('仅保存 UID/SAK/ATQA'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveIdentityOnly() async {
    final info = _basicInfo;
    if (info == null) return;
    final card = CardSave(
      uid: bytesToHexSpace(info.uid),
      name: _name.isEmpty ? 'Card ${bytesToHexSpace(info.uid)}' : _name,
      tag: TagType.hf14a4,
      sak: info.sak,
      atqa: info.atqa,
      ats: info.ats,
      data: const [],
    );
    final prefs = context.read<SharedPreferencesProvider>();
    final cards = prefs.getCards()..add(card);
    prefs.setCards(cards);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存到卡包')));
    Navigator.of(context).pop();
  }

  String _keyText(MifareClassicRecovery recovery, int sector, int keyType) {
    final state = recovery.getSectorState(sector, keyType);
    if (state == ChameleonKeyCheckmark.found) {
      final key = recovery.getSectorKey(sector, keyType);
      return bytesToHex(key).toUpperCase();
    }
    if (state == ChameleonKeyCheckmark.checking) return '检测中...';
    if (state == ChameleonKeyCheckmark.disabled) return '不适用';
    return '未找到';
  }
}
