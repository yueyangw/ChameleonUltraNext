import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';
import 'package:chameleon_ultra_next/ui/pages/hf_sniff_page.dart';
import 'package:chameleon_ultra_next/ui/pages/lf_sniff_page.dart';

/// Per-slot configuration and card preview.
class SlotConfigPage extends StatefulWidget {
  const SlotConfigPage({super.key, required this.slotIndex});

  final int slotIndex;

  @override
  State<SlotConfigPage> createState() => _SlotConfigPageState();
}

class _SlotConfigPageState extends State<SlotConfigPage> {
  TagType _hfType = TagType.unknown;
  TagType _lfType = TagType.unknown;
  bool _hfEnabled = false;
  bool _lfEnabled = false;
  String _hfName = '';
  String _lfName = '';
  String _hfDetail = '未读取';
  String _lfDetail = '未读取';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<ChameleonGUIState>();
    final comm = state.communicator;
    if (comm == null) return;
    setState(() => _loading = true);
    try {
      final types = state.supports16Slots
          ? await comm.getSlotTagTypesV2()
          : await comm.getSlotTagTypes();
      final enabled = state.supports16Slots
          ? await comm.getEnabledSlotsV2()
          : await comm.getEnabledSlots();
      if (!mounted) return;
      setState(() {
        _hfType = types[widget.slotIndex].hf;
        _lfType = types[widget.slotIndex].lf;
        _hfEnabled = enabled[widget.slotIndex].hf;
        _lfEnabled = enabled[widget.slotIndex].lf;
      });
      try {
        _hfName = await comm.getSlotTagName(widget.slotIndex, TagFrequency.hf);
      } catch (_) {}
      try {
        _lfName = await comm.getSlotTagName(widget.slotIndex, TagFrequency.lf);
      } catch (_) {}
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _snack('读取卡槽失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _activate() async {
    final state = context.read<ChameleonGUIState>();
    await state.activateSlot(widget.slotIndex);
    if (mounted) _snack('已切换到卡槽 ${widget.slotIndex + 1}');
  }

  Future<void> _toggleHf(bool value) async {
    final state = context.read<ChameleonGUIState>();
    await state.setSlotEnabled(widget.slotIndex, TagFrequency.hf, value);
    setState(() => _hfEnabled = value);
  }

  Future<void> _toggleLf(bool value) async {
    final state = context.read<ChameleonGUIState>();
    await state.setSlotEnabled(widget.slotIndex, TagFrequency.lf, value);
    setState(() => _lfEnabled = value);
  }

  Future<void> _rename(TagFrequency frequency) async {
    final controller = TextEditingController(
      text: frequency == TagFrequency.hf ? _hfName : _lfName,
    );
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
    if (result == null || result.trim().isEmpty) return;
    final state = context.read<ChameleonGUIState>();
    await state.setSlotName(widget.slotIndex, frequency, result.trim());
    if (frequency == TagFrequency.hf) {
      setState(() => _hfName = result.trim());
    } else {
      setState(() => _lfName = result.trim());
    }
  }

  Future<void> _readSlotCard() async {
    final state = context.read<ChameleonGUIState>();
    final comm = state.communicator;
    if (comm == null) return;
    setState(() => _loading = true);
    try {
      if (_hfType != TagType.unknown) {
        try {
          final data = await comm.mf1GetEmulatorBlock(0, 64);
          final uid = data.length >= 16
              ? bytesToHexSpace(data.sublist(0, 4))
              : '不可用';
          setState(() => _hfDetail = 'UID: $uid · ${data.length} 字节');
        } catch (_) {
          setState(() => _hfDetail = '设备不支持读取该高频卡');
        }
      }
      if (_lfType != TagType.unknown) {
        try {
          final uid = await comm.getEM410XEmulatorID();
          setState(() => _lfDetail = 'UID: ${bytesToHexSpace(uid)}');
        } catch (_) {
          setState(() => _lfDetail = '设备不支持读取该低频卡');
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveToWallet() async {
    final state = context.read<ChameleonGUIState>();
    final prefs = context.read<SharedPreferencesProvider>();
    final comm = state.communicator;
    if (comm == null) return;
    try {
      Uint8List uid = Uint8List(0);
      List<Uint8List> blocks = const <Uint8List>[];
      if (_hfType != TagType.unknown) {
        try {
          final data = await comm.mf1GetEmulatorBlock(0, 64);
          if (data.length >= 16) {
            blocks = [data];
            uid = Uint8List.fromList(data.sublist(0, 4));
          }
        } catch (_) {}
        if (uid.isEmpty) {
          // Some firmware versions do not expose the emulator block data,
          // but they still answer the anti-collision query with the UID.
          try {
            final card = await comm.mf1GetAntiCollData();
            uid = card.uid;
          } catch (_) {}
        }
      } else if (_lfType != TagType.unknown) {
        uid = await comm.getEM410XEmulatorID();
      }
      if (uid.isEmpty) {
        _snack('当前卡槽没有可保存的卡片数据');
        return;
      }
      final card = CardSave(
        uid: bytesToHexSpace(uid),
        name: _hfName.isNotEmpty ? _hfName : _lfDetail,
        tag: _hfType != TagType.unknown ? _hfType : _lfType,
        data: blocks,
      );
      final cards = prefs.getCards()..add(card);
      prefs.setCards(cards);
      _snack('已保存到手机卡包');
    } catch (e) {
      _snack('保存失败: $e');
    }
  }

  Future<void> _overwriteFromWallet() async {
    final prefs = context.read<SharedPreferencesProvider>();
    final cards = prefs.getCards();
    if (cards.isEmpty) return;
    final card = await showModalBottomSheet<CardSave>(
      context: context,
      builder: (context) => ListView(
        children: [
          for (final c in cards)
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: Text(c.name.isEmpty ? c.uid : c.name),
              subtitle: Text(c.tag.name),
              onTap: () => Navigator.pop(context, c),
            ),
        ],
      ),
    );
    if (card == null) return;
    final state = context.read<ChameleonGUIState>();
    final comm = state.communicator;
    if (comm == null) return;
    try {
      await comm.activateSlot(widget.slotIndex);
      if (card.data.isNotEmpty && card.data.first.length >= 16) {
        await comm.setMf1BlockData(0, Uint8List.fromList(
          card.data.expand((e) => e).toList(),
        ));
        await comm.saveSlotData();
        setState(() => _hfType = card.tag);
      } else {
        await comm.setEM410XEmulatorID(hexToBytes(card.uid.replaceAll(' ', '')));
        setState(() => _lfType = card.tag);
      }
      await _load();
      _snack('已覆盖卡槽 ${widget.slotIndex + 1}');
    } catch (e) {
      _snack('覆盖失败: $e');
    }
  }

  Future<void> _sniffHf() async {
    await _activate();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const HfSniffPage()),
    );
  }

  Future<void> _sniffLf() async {
    await _activate();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LfSniffPage()),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _hfName.isNotEmpty
        ? _hfName
        : (_lfName.isNotEmpty ? _lfName : '卡槽 ${widget.slotIndex + 1}');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            _frequencyCard(
              theme,
              frequency: '高频 HF',
              color: Colors.orange,
              icon: Icons.wifi,
              type: _hfType,
              enabled: _hfEnabled,
              name: _hfName,
              detail: _hfDetail,
              onToggle: _toggleHf,
              onRename: () => _rename(TagFrequency.hf),
            ),
            const SizedBox(height: 12),
            _frequencyCard(
              theme,
              frequency: '低频 LF',
              color: Colors.blue,
              icon: Icons.graphic_eq,
              type: _lfType,
              enabled: _lfEnabled,
              name: _lfName,
              detail: _lfDetail,
              onToggle: _toggleLf,
              onRename: () => _rename(TagFrequency.lf),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _activate,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('设为当前卡槽'),
                ),
                OutlinedButton.icon(
                  onPressed: _readSlotCard,
                  icon: const Icon(Icons.download),
                  label: const Text('读取卡槽卡片'),
                ),
                OutlinedButton.icon(
                  onPressed: _saveToWallet,
                  icon: const Icon(Icons.wallet),
                  label: const Text('保存到卡包'),
                ),
                OutlinedButton.icon(
                  onPressed: _overwriteFromWallet,
                  icon: const Icon(Icons.upload),
                  label: const Text('用卡包覆盖'),
                ),
                OutlinedButton.icon(
                  onPressed: _sniffHf,
                  icon: const Icon(Icons.radar),
                  label: const Text('用此卡槽嗅探 HF'),
                ),
                OutlinedButton.icon(
                  onPressed: _sniffLf,
                  icon: const Icon(Icons.sensors),
                  label: const Text('用此卡槽嗅探 LF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _frequencyCard(
    ThemeData theme, {
    required String frequency,
    required Color color,
    required IconData icon,
    required TagType type,
    required bool enabled,
    required String name,
    required String detail,
    required ValueChanged<bool> onToggle,
    required VoidCallback onRename,
  }) {
    final known = type != TagType.unknown;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.2),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(frequency,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(known ? type.name : '未配置'),
                    ],
                  ),
                ),
                Switch(value: enabled, onChanged: onToggle),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: known ? 1 : 0.08,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(detail)),
                TextButton.icon(
                  onPressed: onRename,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('改名'),
                ),
              ],
            ),
            if (name.isNotEmpty)
              Text(name, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
