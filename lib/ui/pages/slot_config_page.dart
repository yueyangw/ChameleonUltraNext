import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/general.dart';
import 'package:chameleon_ultra_next/helpers/mfkey32_recover.dart';
import 'package:chameleon_ultra_next/helpers/slot_write.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';
import 'package:chameleon_ultra_next/ui/pages/hf_sniff_page.dart';
import 'package:chameleon_ultra_next/ui/pages/lf_sniff_page.dart';

/// Detail page of one emulation slot, split into HF / LF / sniff tabs.
class SlotConfigPage extends StatefulWidget {
  const SlotConfigPage({super.key, required this.slotIndex});

  final int slotIndex;

  @override
  State<SlotConfigPage> createState() => _SlotConfigPageState();
}

class _SlotConfigPageState extends State<SlotConfigPage> {
  bool _busy = false;
  int? _progress;
  String _hfDetail = '';
  final _hfQuery = ValueNotifier<String>('');
  final _lfQuery = ValueNotifier<String>('');

  // Sniff tab
  bool _detecting = false;
  int _detectCount = 0;
  int? _slotUid;
  final List<RecoveredKey> _keys = [];

  int get _slot => widget.slotIndex;

  @override
  void dispose() {
    _hfQuery.dispose();
    _lfQuery.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs [action] exclusively: blocks the UI, pauses the background status
  /// poll and reports errors, then refreshes the shared device state.
  Future<bool> _run(
    Future<void> Function() action, {
    String? success,
    bool refresh = true,
  }) async {
    if (_busy) return false;
    final state = context.read<ChameleonGUIState>();
    if (state.communicator == null) {
      _snack('未连接设备');
      return false;
    }
    setState(() {
      _busy = true;
      _progress = null;
    });
    state.pauseRefresh();
    var ok = false;
    try {
      await action();
      ok = true;
      if (success != null) _snack(success);
    } catch (e) {
      _snack('操作失败: $e');
    } finally {
      state.resumeRefresh();
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
    if (refresh && mounted) await state.refreshAll();
    return ok;
  }

  Future<void> _activate() async {
    final state = context.read<ChameleonGUIState>();
    await _run(
      () => state.activateSlot(_slot),
      success: '已切换到卡槽 ${_slot + 1}',
      refresh: false,
    );
  }

  Future<void> _toggle(TagFrequency frequency, bool value) async {
    final state = context.read<ChameleonGUIState>();
    await _run(
      () => state.setSlotEnabled(_slot, frequency, value),
      refresh: false,
    );
  }

  Future<void> _rename(TagFrequency frequency, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(frequency == TagFrequency.hf ? '重命名高频卡槽' : '重命名低频卡槽'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入卡片名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty || !mounted) return;
    final state = context.read<ChameleonGUIState>();
    await _run(
      () => state.setSlotName(_slot, frequency, result.trim()),
      refresh: false,
    );
  }

  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // --- Current card -------------------------------------------------------

  Future<void> _readHfDetail() async {
    final state = context.read<ChameleonGUIState>();
    await _run(() async {
      final comm = state.communicator!;
      await comm.activateSlot(_slot);
      final card = await comm.mf1GetAntiCollData();
      if (!mounted) return;
      setState(() {
        _hfDetail =
            'UID ${bytesToHexSpace(card.uid)}'
            ' · SAK ${card.sak.toRadixString(16).padLeft(2, '0').toUpperCase()}'
            ' · ATQA ${bytesToHexSpace(card.atqa)}';
      });
    }, refresh: false);
  }

  Future<void> _download(TagFrequency frequency) async {
    final state = context.read<ChameleonGUIState>();
    final prefs = context.read<SharedPreferencesProvider>();
    final types = state.slotTypes[_slot];
    final type = frequency == TagFrequency.hf ? types.hf : types.lf;
    if (type == TagType.unknown) {
      _snack('当前${frequency == TagFrequency.hf ? '高频' : '低频'}卡槽没有卡片');
      return;
    }
    final nick = frequency == TagFrequency.hf
        ? state.hfNames[_slot]
        : state.lfNames[_slot];
    final name = nick.isNotEmpty
        ? nick
        : '卡槽 ${_slot + 1} ${frequency == TagFrequency.hf ? 'HF' : 'LF'}';

    CardSave? card;
    final ok = await _run(() async {
      card = await readCardSaveFromSlot(
        state.communicator!,
        _slot,
        frequency,
        type,
        name,
      );
    }, refresh: false);
    if (!ok || card == null || !mounted) return;

    final cards = prefs.getCards();
    final dup = cards.indexWhere(
      (c) => c.uid == card!.uid && c.tag == card!.tag,
    );
    if (dup >= 0) {
      final overwrite = await _confirm(
        '卡包中已有相同卡片',
        '「${cards[dup].name}」的 UID 和类型相同，是否覆盖？选择取消将另存为新卡。',
      );
      if (!mounted) return;
      if (overwrite) {
        card!.id = cards[dup].id;
        card!.folderId = cards[dup].folderId;
        cards[dup] = card!;
      } else {
        cards.add(card!);
      }
    } else {
      cards.add(card!);
    }
    prefs.setCards(cards);
    _snack('已下载到卡包: ${card!.name}');
  }

  Future<void> _clear(TagFrequency frequency) async {
    if (!await _confirm('清空卡槽', '确定清空卡槽 ${_slot + 1} 的该频率卡片？')) return;
    if (!mounted) return;
    final state = context.read<ChameleonGUIState>();
    await _run(() async {
      await state.communicator!.deleteSlotInfo(_slot, frequency);
      await state.communicator!.saveSlotData();
    }, success: '已清空');
  }

  Future<void> _replace(CardSave card) async {
    final frequency = chameleonTagToFrequency(card.tag);
    if (!await _confirm(
      '替换卡片',
      '用「${card.name}」(${card.tag.name}) 覆盖卡槽 ${_slot + 1} 的'
          '${frequency == TagFrequency.hf ? '高频' : '低频'}卡片？',
    )) {
      return;
    }
    if (!mounted) return;
    final state = context.read<ChameleonGUIState>();
    await _run(() async {
      await writeCardSaveToSlot(
        state.communicator!,
        _slot,
        card,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    }, success: '已写入卡槽 ${_slot + 1}');
  }

  // --- Sniff --------------------------------------------------------------

  Future<void> _refreshDetection() async {
    final state = context.read<ChameleonGUIState>();
    await _run(() async {
      final comm = state.communicator!;
      final mode = await comm.isMf1DetectionMode();
      final count = await comm.getMf1DetectionCount();
      if (!mounted) return;
      setState(() {
        _detecting = mode;
        _detectCount = count;
      });
    }, refresh: false);
  }

  Future<void> _toggleDetection(bool value) async {
    final state = context.read<ChameleonGUIState>();
    await _run(() async {
      final comm = state.communicator!;
      await comm.activateSlot(_slot);
      await comm.setMf1DetectionStatus(value);
      final mode = await comm.isMf1DetectionMode();
      final count = await comm.getMf1DetectionCount();
      final card = await comm.mf1GetAntiCollData();
      if (!mounted) return;
      setState(() {
        _detecting = mode;
        _detectCount = count;
        _slotUid = detectionUidOf(bytesToHexSpace(card.uid));
      });
    }, refresh: false);
  }

  Future<void> _recoverKeys() async {
    final state = context.read<ChameleonGUIState>();
    await _run(() async {
      final comm = state.communicator!;
      if (_slotUid == null) {
        await comm.activateSlot(_slot);
        final card = await comm.mf1GetAntiCollData();
        _slotUid = detectionUidOf(bytesToHexSpace(card.uid));
      }
      if (mounted) setState(_keys.clear);
      final found = await recoverMfkey32(
        comm,
        _detectCount,
        uidFilter: _slotUid,
        onKey: (key) {
          if (mounted) setState(() => _keys.add(key));
        },
      );
      if (found.isEmpty) _snack('没有可恢复的 nonce 组（需要同一扇区至少两次认证）');
    }, refresh: false);
  }

  void _saveKeyToWallet(RecoveredKey key) {
    final prefs = context.read<SharedPreferencesProvider>();
    final cards = prefs.getCards();
    var updated = 0;
    for (final card in cards) {
      if (!isMifareClassic(card.tag)) continue;
      if (detectionUidOf(card.uid) != key.uid) continue;
      final trailer = mfClassicGetSectorTrailerBlockBySector(
        mfClassicGetSectorByBlock(key.block),
      );
      if (trailer >= card.data.length || card.data[trailer].length != 16) {
        continue;
      }
      final keyBytes = hexToBytes(key.key);
      final offset = key.keyType == 'A' ? 0 : 10;
      final block = Uint8List.fromList(card.data[trailer]);
      block.setRange(offset, offset + 6, keyBytes);
      card.data[trailer] = block;
      updated++;
    }
    if (updated == 0) {
      _snack('卡包中没有 UID 匹配且含数据的 MIFARE Classic 卡');
      return;
    }
    prefs.setCards(cards);
    _snack('已更新卡包中 $updated 张卡的 Key${key.keyType}');
  }

  Future<void> _openSniff(Widget page) async {
    final state = context.read<ChameleonGUIState>();
    final ok = await _run(() => state.activateSlot(_slot), refresh: false);
    if (!ok || !mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  }

  // --- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ChameleonGUIState>();
    final inRange =
        _slot < state.slotTypes.length &&
        _slot < state.enabledSlots.length &&
        _slot < state.hfNames.length &&
        _slot < state.lfNames.length;
    final nick = inRange
        ? (state.hfNames[_slot].isNotEmpty
              ? state.hfNames[_slot]
              : state.lfNames[_slot])
        : '';
    final title = nick.isNotEmpty ? nick : '卡槽 ${_slot + 1}';

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              tooltip: state.activeSlot == _slot ? '当前卡槽' : '设为当前卡槽',
              onPressed: _busy || state.activeSlot == _slot ? null : _activate,
              icon: Icon(
                state.activeSlot == _slot
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '高频 HF'),
              Tab(text: '低频 LF'),
              Tab(text: '嗅探'),
            ],
          ),
        ),
        body: !inRange
            ? const Center(child: Text('卡槽数据尚未加载，请返回后刷新'))
            : Column(
                children: [
                  if (_busy)
                    LinearProgressIndicator(
                      value: _progress == null ? null : _progress! / 100,
                    ),
                  if (state.pollingStatus?.running ?? false)
                    MaterialBanner(
                      content: const Text('卡槽轮询正在运行，读写卡槽会切换激活卡槽并停止本次轮询。'),
                      actions: const [SizedBox.shrink()],
                    ),
                  Expanded(
                    child: AbsorbPointer(
                      absorbing: _busy,
                      child: TabBarView(
                        children: [
                          _frequencyTab(state, TagFrequency.hf),
                          _frequencyTab(state, TagFrequency.lf),
                          _sniffTab(state),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _frequencyTab(ChameleonGUIState state, TagFrequency frequency) {
    final isHf = frequency == TagFrequency.hf;
    final theme = Theme.of(context);
    final type = isHf ? state.slotTypes[_slot].hf : state.slotTypes[_slot].lf;
    final enabled = isHf
        ? state.enabledSlots[_slot].hf
        : state.enabledSlots[_slot].lf;
    final name = isHf ? state.hfNames[_slot] : state.lfNames[_slot];
    final known = type != TagType.unknown;
    final color = isHf ? Colors.orange : Colors.blue;
    final query = isHf ? _hfQuery : _lfQuery;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.2),
                      child: Icon(
                        isHf ? Icons.wifi : Icons.graphic_eq,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            known ? type.name : '未配置',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (name.isNotEmpty)
                            Text(name, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Switch(
                      value: enabled,
                      onChanged: known ? (v) => _toggle(frequency, v) : null,
                    ),
                  ],
                ),
                if (isHf && known && _hfDetail.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(_hfDetail),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: known ? () => _download(frequency) : null,
                      icon: const Icon(Icons.download),
                      label: const Text('下载到卡包'),
                    ),
                    if (isHf)
                      OutlinedButton.icon(
                        onPressed: known ? _readHfDetail : null,
                        icon: const Icon(Icons.info_outline),
                        label: const Text('读取详情'),
                      ),
                    OutlinedButton.icon(
                      onPressed: known ? () => _rename(frequency, name) : null,
                      icon: const Icon(Icons.edit),
                      label: const Text('改名'),
                    ),
                    OutlinedButton.icon(
                      onPressed: known ? () => _clear(frequency) : null,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('清空'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '卡包 · ${isHf ? '高频' : '低频'}卡片',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '搜索卡名或 UID',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => query.value = v,
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<String>(
          valueListenable: query,
          builder: (context, q, _) {
            final prefs = context.watch<SharedPreferencesProvider>();
            final needle = q.toLowerCase();
            final cards = prefs
                .getCards()
                .where((c) => cardMatchesFrequency(c, frequency))
                .where(
                  (c) =>
                      needle.isEmpty ||
                      c.name.toLowerCase().contains(needle) ||
                      c.uid.toLowerCase().contains(needle),
                )
                .toList();
            if (cards.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('卡包里没有匹配的卡片')),
              );
            }
            return Column(
              children: [
                for (final c in cards)
                  Card(
                    child: ListTile(
                      leading: Icon(isHf ? Icons.nfc : Icons.sensors),
                      title: Text(c.name.isEmpty ? c.uid : c.name),
                      subtitle: Text('${c.uid} · ${c.tag.name}'),
                      trailing: FilledButton.tonal(
                        onPressed: () => _replace(c),
                        child: const Text('替换'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _sniffTab(ChameleonGUIState state) {
    final theme = Theme.of(context);
    final hfType = state.slotTypes[_slot].hf;
    final mf1 = isMifareClassic(hfType);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('MF1 侦测 (mfkey32)', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (!mf1)
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('该卡槽的高频卡不是 MIFARE Classic，无法侦测读卡器认证'),
            ),
          )
        else ...[
          Card(
            child: SwitchListTile(
              title: const Text('侦测读卡器认证'),
              subtitle: Text(_detecting ? '已启用，正在记录 nonce' : '未启用'),
              value: _detecting,
              onChanged: _toggleDetection,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('已记录 nonce'),
              subtitle: Text('$_detectCount 组'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refreshDetection,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _detectCount == 0 ? null : _recoverKeys,
            icon: const Icon(Icons.key),
            label: const Text('计算密钥'),
          ),
          for (final key in _keys)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: SelectableText(key.toString()),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: '复制',
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: key.key));
                        _snack('已复制');
                      },
                    ),
                    IconButton(
                      tooltip: '写回卡包',
                      icon: const Icon(Icons.save_alt),
                      onPressed: () => _saveKeyToWallet(key),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),
        Text('嗅探', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.radar),
            title: const Text('HF 嗅探'),
            subtitle: const Text('切换到此卡槽后抓取 14443A 通信'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openSniff(const HfSniffPage()),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.sensors),
            title: const Text('LF 嗅探'),
            subtitle: const Text('切换到此卡槽后抓取 125 kHz 信号'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openSniff(const LfSniffPage()),
          ),
        ),
      ],
    );
  }
}
