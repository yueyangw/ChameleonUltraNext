import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/helpers/slot_write.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';
import 'package:chameleon_ultra_next/ui/pages/attack_page.dart';
import 'package:chameleon_ultra_next/ui/pages/read_card_page.dart';
import 'package:chameleon_ultra_next/ui/pages/dump_editor_page.dart';
import 'package:chameleon_ultra_next/ui/widgets/dump_widgets.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  String _query = '';
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  List<CardSave> _cards(SharedPreferencesProvider prefs) {
    final cards = prefs.getCards();
    if (_query.isEmpty) return cards;
    final q = _query.toLowerCase();
    return cards
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.uid.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _chooseReadType(SharedPreferencesProvider prefs) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.nfc),
              title: const Text('读取 HF 13.56 MHz'),
              subtitle: const Text('UID、扇区密钥、完整 dump，逐步引导'),
              onTap: () => Navigator.pop(context, 'hf'),
            ),
            ListTile(
              leading: const Icon(Icons.flash_on),
              title: const Text('快速读取 HF（默认密钥）'),
              subtitle: const Text('只用常见默认密钥尝试，适合空白/未加密卡'),
              onTap: () => Navigator.pop(context, 'hf-quick'),
            ),
            ListTile(
              leading: const Icon(Icons.sensors),
              title: const Text('读取 LF 125 kHz'),
              subtitle: const Text('EM410x / HID Prox / Viking / Jablotron'),
              onTap: () => Navigator.pop(context, 'lf'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'hf') {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const ReadCardPage()));
    }
    if (choice == 'hf-quick') await _readCard(prefs);
    if (choice == 'lf') await _readLfCard(prefs);
  }

  Future<void> _readLfCard(SharedPreferencesProvider prefs) async {
    final state = context.read<ChameleonGUIState>();
    final comm = state.communicator;
    if (comm == null) return;
    final messenger = ScaffoldMessenger.of(context);
    var switchedMode = false;
    state.pauseRefresh();
    try {
      if (!await comm.isReaderDeviceMode()) {
        await comm.setReaderDeviceMode(true);
        switchedMode = true;
      }
      final card = await comm.readEM410X();
      if (card == null) {
        messenger.showSnackBar(const SnackBar(content: Text('未检测到 LF 卡')));
        return;
      }
      final uid = card.toString();
      final save = CardSave(uid: uid, name: 'LF $uid', tag: card.type);
      final all = prefs.getCards()..add(save);
      prefs.setCards(all);
      if (mounted) setState(() {});
      messenger.showSnackBar(const SnackBar(content: Text('LF 卡已保存到卡包')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('LF 读卡失败：$e')));
    } finally {
      if (switchedMode) {
        try {
          await comm.setReaderDeviceMode(false);
        } catch (_) {}
      }
      state.resumeRefresh();
    }
  }

  Future<void> _readCard(SharedPreferencesProvider prefs) async {
    final state = context.read<ChameleonGUIState>();
    final comm = state.communicator;
    if (comm == null) return;
    final messenger = ScaffoldMessenger.of(context);
    var switchedMode = false;
    state.pauseRefresh();
    try {
      if (!await comm.isReaderDeviceMode()) {
        await comm.setReaderDeviceMode(true);
        switchedMode = true;
      }
      final card = await comm.scan14443aTag();
      if (card == null) {
        messenger.showSnackBar(const SnackBar(content: Text('未检测到卡片')));
        return;
      }
      final tag = _tagTypeForSak(card.sak);
      final blocks = <Uint8List>[];
      var unreadable = 0;
      if (tag == TagType.mifare1K ||
          tag == TagType.mifare4K ||
          tag == TagType.mifareMini) {
        final total = getBlockCountForTagType(tag);
        final defaultKey = Uint8List.fromList(List<int>.filled(6, 0xFF));
        var sectorFailed = false;
        for (var block = 0; block < total; block++) {
          // Keep block numbers contiguous: a failed read is padded with zeros
          // instead of being skipped, otherwise the dump would shift.
          final sectorStart = _isSectorStart(block);
          if (sectorStart) sectorFailed = false;
          Uint8List data = Uint8List(0);
          if (!sectorFailed) {
            try {
              data = await comm.mf1ReadBlock(block, 0x60, defaultKey);
            } catch (_) {}
          }
          if (data.length >= 16) {
            blocks.add(Uint8List.fromList(data.sublist(0, 16)));
          } else {
            // Wrong key for this sector: do not retry every block of it.
            sectorFailed = true;
            unreadable++;
            blocks.add(Uint8List(16));
          }
        }
      }
      final name =
          'Card ${card.uid.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}';
      final save = CardSave(
        uid: bytesToHexSpace(card.uid),
        name: name,
        tag: tag,
        sak: card.sak,
        atqa: card.atqa,
        ats: card.ats,
        data: blocks,
      );
      final all = prefs.getCards()..add(save);
      prefs.setCards(all);
      if (mounted) setState(() {});
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            unreadable == 0
                ? '卡片已保存到卡包'
                : '卡片已保存，但有 $unreadable 个块使用默认密钥无法读取，已用 0 填充',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('读卡失败：$e')));
    } finally {
      if (switchedMode) {
        try {
          await comm.setReaderDeviceMode(false);
        } catch (_) {}
      }
      state.resumeRefresh();
    }
  }

  void _toggleSelecting() {
    setState(() {
      _selecting = !_selecting;
      if (!_selecting) _selected.clear();
    });
  }

  Future<void> _deleteSelected(SharedPreferencesProvider prefs) async {
    if (_selected.isEmpty) return;
    if (!await _confirmDelete(
        '删除 ${_selected.length} 张卡片', '确定删除选中的卡片？此操作不可撤销。')) {
      return;
    }
    final cards = prefs.getCards()
      ..removeWhere((c) => _selected.contains(c.id));
    prefs.setCards(cards);
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除')),
    );
  }

  Future<bool> _confirmDelete(String title, String message) async {
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
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  static bool _isSectorStart(int block) =>
      block < 128 ? block % 4 == 0 : (block - 128) % 16 == 0;

  static TagType _tagTypeForSak(int sak) {
    switch (sak & 0xFF) {
      case 0x08:
        return TagType.mifare1K;
      case 0x18:
        return TagType.mifare4K;
      case 0x09:
        return TagType.mifareMini;
      default:
        return TagType.mifare1K;
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<SharedPreferencesProvider>();
    final cards = _cards(prefs);
    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? '已选 ${_selected.length} 张' : '卡包'),
        actions: [
          if (_selecting && _selected.isNotEmpty)
            IconButton(
              tooltip: '删除选中',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteSelected(prefs),
            ),
          if (cards.isNotEmpty)
            IconButton(
              tooltip: _selecting ? '完成' : '多选删除',
              icon: Icon(_selecting ? Icons.close : Icons.checklist),
              onPressed: _toggleSelecting,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索卡名或 UID',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _chooseReadType(prefs),
        icon: const Icon(Icons.add),
        label: const Text('读取卡片'),
      ),
      body: cards.isEmpty
          ? const Center(child: Text('卡包为空，先读取一张卡'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: cards.length,
              itemBuilder: (context, index) {
                final card = cards[index];
                final selected = _selected.contains(card.id);
                final tile = Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: ListTile(
                    leading: _selecting
                        ? Checkbox(
                            value: selected,
                            onChanged: (_) => setState(() {
                              if (selected) {
                                _selected.remove(card.id);
                              } else {
                                _selected.add(card.id);
                              }
                            }),
                          )
                        : const Icon(Icons.credit_card),
                    title: Text(card.name),
                    subtitle: Text('${card.uid} · ${card.tag.name}'),
                    trailing: _selecting
                        ? null
                        : const Icon(Icons.chevron_right),
                    onTap: _selecting
                        ? () => setState(() {
                              if (selected) {
                                _selected.remove(card.id);
                              } else {
                                _selected.add(card.id);
                              }
                            })
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CardDetailPage(card: card),
                              ),
                            ),
                    onLongPress: _selecting
                        ? null
                        : () => setState(() {
                              _selecting = true;
                              _selected.add(card.id);
                            }),
                  ),
                );
                if (_selecting) return tile;
                return Dismissible(
                  key: ValueKey(card.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.centerRight,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                  confirmDismiss: (_) => _confirmDelete(
                      '删除卡片', '确定删除「${card.name.isEmpty ? card.uid : card.name}」？此操作不可撤销。'),
                  onDismissed: (_) {
                    final updated = prefs.getCards()
                      ..removeWhere((c) => c.id == card.id);
                    prefs.setCards(updated);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('已删除')));
                  },
                  child: tile,
                );
              },
            ),
    );
  }
}

class CardDetailPage extends StatefulWidget {
  const CardDetailPage({super.key, required this.card});
  final CardSave card;

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  late CardSave card = widget.card;

  Future<void> _editDump() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DumpEditorPage(initialCardId: card.id),
      ),
    );
    if (!mounted) return;
    // The editor saves straight into the wallet; pick the result up again.
    final fresh = context
        .read<SharedPreferencesProvider>()
        .getCards()
        .where((c) => c.id == card.id)
        .firstOrNull;
    if (fresh != null) setState(() => card = fresh);
  }

  Future<void> _writeToSlot(BuildContext context) async {
    final state = context.read<ChameleonGUIState>();
    final comm = state.communicator;
    if (comm == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final frequency = chameleonTagToFrequency(card.tag);
    final count = state.slotTypes.length;
    final slot = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('写入${frequency == TagFrequency.hf ? '高频' : '低频'}卡槽'),
        children: [
          for (var i = 0; i < count; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i),
              child: Text(
                '卡槽 ${i + 1}  |  '
                '${frequency == TagFrequency.hf ? state.slotTypes[i].hf.name : state.slotTypes[i].lf.name}',
              ),
            ),
        ],
      ),
    );
    if (slot == null) return;
    state.pauseRefresh();
    try {
      await writeCardSaveToSlot(comm, slot, card);
      messenger.showSnackBar(SnackBar(content: Text('已写入卡槽 ${slot + 1}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('写入失败：$e')));
    } finally {
      state.resumeRefresh();
    }
    await state.refreshAll();
  }

  Future<void> _delete(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除卡片'),
        content: Text(
            '确定删除「${card.name.isEmpty ? card.uid : card.name}」？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final prefs = context.read<SharedPreferencesProvider>();
    final cards = prefs.getCards()..removeWhere((c) => c.id == card.id);
    prefs.setCards(cards);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(card.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_open),
            tooltip: '密钥恢复',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const AttackPage())),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: () => _delete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.name, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('UID: ${card.uid}'),
                  Text('类型: ${card.tag.name}'),
                  Text(
                    'SAK: ${card.sak.toRadixString(16).padLeft(2, '0').toUpperCase()}',
                  ),
                  Text('ATQA: ${bytesToHexSpace(card.atqa)}'),
                  if (card.ats.isNotEmpty)
                    Text('ATS: ${bytesToHexSpace(card.ats)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _writeToSlot(context),
            icon: const Icon(Icons.save_alt),
            label: const Text('写入卡槽'),
          ),
          const SizedBox(height: 12),
          if (card.data.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Dump 数据 (${card.data.length})',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _editDump,
                  icon: const Icon(Icons.edit),
                  label: const Text('编辑 Dump'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Card(
              clipBehavior: Clip.antiAlias,
              child: DumpView(tag: card.tag, uid: card.uid, blocks: card.data),
            ),
          ],
        ],
      ),
    );
  }
}
