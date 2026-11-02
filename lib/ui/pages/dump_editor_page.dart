import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/general.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';
import 'package:chameleon_ultra_next/ui/widgets/block_editors.dart';
import 'package:chameleon_ultra_next/ui/widgets/dump_widgets.dart';

/// Field-aware dump editor: tap a block to edit its UID / keys / access bits
/// / bytes instead of retyping a whole hex line.
class DumpEditorPage extends StatefulWidget {
  const DumpEditorPage({super.key, this.initialCardId});

  /// Card to open straight away (skips the picker).
  final String? initialCardId;

  @override
  State<DumpEditorPage> createState() => _DumpEditorPageState();
}

class _DumpEditorPageState extends State<DumpEditorPage> {
  String? _selectedId;
  List<Uint8List> _original = const [];
  List<Uint8List> _blocks = [];
  final Set<int> _dirty = <int>{};

  @override
  void initState() {
    super.initState();
    final id = widget.initialCardId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final card = context
            .read<SharedPreferencesProvider>()
            .getCards()
            .where((c) => c.id == id)
            .firstOrNull;
        if (card != null) setState(() => _load(card));
      });
    }
  }

  void _load(CardSave card) {
    _selectedId = card.id;
    _original = [for (final b in card.data) Uint8List.fromList(b)];
    _blocks = [for (final b in card.data) Uint8List.fromList(b)];
    _dirty.clear();
  }

  Future<bool> _confirmDiscard() async {
    if (_dirty.isEmpty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: Text('有 ${_dirty.length} 个块已修改但尚未保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _edit(CardSave card, int index) async {
    final edited = await showBlockEditor(
      context,
      tag: card.tag,
      index: index,
      data: _blocks[index],
      uid: card.uid,
    );
    if (edited == null || !mounted) return;
    setState(() {
      _blocks[index] = edited;
      if (_sameBytes(edited, _original[index])) {
        _dirty.remove(index);
      } else {
        _dirty.add(index);
      }
    });
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _save(CardSave original) {
    final updated = CardSave(
      id: original.id,
      uid: original.uid,
      name: original.name,
      tag: original.tag,
      sak: original.sak,
      atqa: original.atqa,
      ats: original.ats,
      color: original.color,
      folderId: original.folderId,
      data: [for (final b in _blocks) Uint8List.fromList(b)],
      extraData: original.extraData,
    );
    final prefs = context.read<SharedPreferencesProvider>();
    final cards = prefs.getCards();
    final index = cards.indexWhere((card) => card.id == updated.id);
    if (index >= 0) {
      cards[index] = updated;
    } else {
      cards.add(updated);
    }
    prefs.setCards(cards);
    setState(() {
      _original = [for (final b in _blocks) Uint8List.fromList(b)];
      _dirty.clear();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存')));
  }

  Future<void> _bulkKeys() async {
    final controllerA = TextEditingController();
    final controllerB = TextEditingController();
    final result = await showDialog<(String?, String?)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量设置所有扇区密钥'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controllerA,
              maxLength: 12,
              decoration: const InputDecoration(
                labelText: 'Key A（留空则不改）',
                helperText: '12 位十六进制',
              ),
            ),
            TextField(
              controller: controllerB,
              maxLength: 12,
              decoration: const InputDecoration(
                labelText: 'Key B（留空则不改）',
                helperText: '12 位十六进制',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              controllerA.text.trim(),
              controllerB.text.trim(),
            )),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    controllerA.dispose();
    controllerB.dispose();
    if (result == null || !mounted) return;
    final hex = RegExp(r'^[0-9A-Fa-f]{12}$');
    final a = result.$1 ?? '';
    final b = result.$2 ?? '';
    if ((a.isNotEmpty && !hex.hasMatch(a)) ||
        (b.isNotEmpty && !hex.hasMatch(b))) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('密钥必须是 12 位十六进制')));
      return;
    }
    setState(() {
      for (var sector = 0; sector < 40; sector++) {
        final trailer = mfClassicGetSectorTrailerBlockBySector(sector);
        if (trailer >= _blocks.length || _blocks[trailer].length != 16) {
          continue;
        }
        final block = Uint8List.fromList(_blocks[trailer]);
        if (a.isNotEmpty) block.setRange(0, 6, hexToBytes(a));
        if (b.isNotEmpty) block.setRange(10, 16, hexToBytes(b));
        _blocks[trailer] = block;
        if (_sameBytes(block, _original[trailer])) {
          _dirty.remove(trailer);
        } else {
          _dirty.add(trailer);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<SharedPreferencesProvider>();
    final cards = prefs.getCards();
    final current = cards.where((card) => card.id == _selectedId).firstOrNull;
    final theme = Theme.of(context);

    return PopScope(
      canPop: _dirty.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(current == null ? 'Dump 编辑器' : current.name),
          actions: [
            if (current != null) ...[
              if (isMifareClassic(current.tag))
                IconButton(
                  tooltip: '批量设置密钥',
                  onPressed: _bulkKeys,
                  icon: const Icon(Icons.vpn_key_outlined),
                ),
              IconButton(
                tooltip: '撤销全部修改',
                onPressed: _dirty.isEmpty
                    ? null
                    : () => setState(() {
                        _blocks = [
                          for (final b in _original) Uint8List.fromList(b),
                        ];
                        _dirty.clear();
                      }),
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: '保存修改',
                onPressed: _dirty.isEmpty ? null : () => _save(current),
                icon: Badge(
                  isLabelVisible: _dirty.isNotEmpty,
                  label: Text('${_dirty.length}'),
                  child: const Icon(Icons.save),
                ),
              ),
            ],
          ],
        ),
        body: Column(
          children: [
            if (widget.initialCardId == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedId,
                  decoration: const InputDecoration(
                    labelText: '选择卡片',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final card in cards)
                      DropdownMenuItem(
                        value: card.id,
                        child: Text(
                          '${card.name} (${card.tag.name})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) async {
                    final selected = cards
                        .where((card) => card.id == value)
                        .firstOrNull;
                    if (selected == null) return;
                    if (!await _confirmDiscard() || !mounted) return;
                    setState(() => _load(selected));
                  },
                ),
              ),
            Expanded(
              child: current == null
                  ? const Center(child: Text('选择一张已保存的卡片'))
                  : _blocks.isEmpty
                  ? const Center(child: Text('该卡片没有可编辑的数据'))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text(
                            '点击任意块按字段修改；已修改的块左侧有标记。',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        DumpView(
                          tag: current.tag,
                          uid: current.uid,
                          blocks: _blocks,
                          dirty: _dirty,
                          onTapBlock: (index) => _edit(current, index),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
