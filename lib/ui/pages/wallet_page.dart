import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/core/models/slot_info.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';
import 'package:chameleon_ultra_next/ui/pages/attack_page.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  String _query = '';

  List<CardSave> _cards(SharedPreferencesProvider prefs) {
    final cards = prefs.getCards();
    if (_query.isEmpty) return cards;
    final q = _query.toLowerCase();
    return cards
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.uid.toLowerCase().contains(q))
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
              subtitle: const Text('MIFARE Classic / NTAG / ISO14443A'),
              onTap: () => Navigator.pop(context, 'hf'),
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
    if (choice == 'hf') await _readCard(prefs);
    if (choice == 'lf') await _readLfCard(prefs);
  }

  Future<void> _readLfCard(SharedPreferencesProvider prefs) async {
    final state = context.read<ChameleonGUIState>();
    final comm = state.communicator;
    if (comm == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await comm.isReaderDeviceMode()) {
        await comm.setReaderDeviceMode(true);
      }
      final card = await comm.readEM410X();
      if (card == null) {
        messenger.showSnackBar(const SnackBar(content: Text('未检测到 LF 卡')));
        return;
      }
      final uid = card.toString();
      final save = CardSave(
        uid: uid,
        name: 'LF ',
        tag: TagType.em410X,
      );
      final all = prefs.getCards()..add(save);
      prefs.setCards(all);
      if (mounted) setState(() {});
      messenger.showSnackBar(const SnackBar(content: Text('LF 卡已保存到卡包')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('LF 读卡失败：')));
    }
  }

  Future<void> _readCard(SharedPreferencesProvider prefs) async {
    final state = context.read<ChameleonGUIState>();
    final comm = state.communicator;
    if (comm == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await comm.isReaderDeviceMode()) {
        await comm.setReaderDeviceMode(true);
      }
      final card = await comm.scan14443aTag();
      if (card == null) {
        messenger.showSnackBar(
            const SnackBar(content: Text('未检测到卡片')));
        return;
      }
      final tag = _tagTypeForSak(card.sak);
      final blocks = <Uint8List>[];
      if (tag == TagType.mifare1K ||
          tag == TagType.mifare4K ||
          tag == TagType.mifareMini) {
        for (var block = 0; block < 64; block++) {
          try {
            final data = await comm.mf1ReadBlock(block, 0x60, Uint8List.fromList(List<int>.filled(6, 0xFF)));
            if (data.length >= 16) blocks.add(data.sublist(0, 16));
          } catch (_) {
            break;
          }
        }
      }
      final name = 'Card ${card.uid.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}';
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
      messenger.showSnackBar(const SnackBar(content: Text('卡片已保存到卡包')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('读卡失败：')));
    }
  }

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
        title: const Text('卡包'),
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
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.credit_card),
                    title: Text(card.name),
                    subtitle: Text('${card.uid} 路 ${card.tag.name}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CardDetailPage(card: card),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class CardDetailPage extends StatelessWidget {
  const CardDetailPage({super.key, required this.card});
  final CardSave card;

  Future<void> _writeToSlot(BuildContext context) async {
    final state = context.read<ChameleonGUIState>();
    final comm = state.communicator;
    if (comm == null) return;
    final slot = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('写入卡槽'),
        children: [
          for (var i = 0; i < state.slotTypes.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i),
              child: Text('卡槽  | '),
            ),
        ],
      ),
    );
    if (slot == null) return;
    try {
      await comm.activateSlot(slot);
      await comm.setSlotType(slot, card.tag);
      if (card.data.isNotEmpty) {
        final flat = <int>[];
        for (final b in card.data) {
          flat.addAll(b);
        }
        await comm.setMf1BlockData(0, Uint8List.fromList(flat));
        await comm.setMf1AntiCollision(CardData(
          uid: hexToBytes(card.uid.replaceAll(' ', '')),
          sak: card.sak,
          atqa: card.atqa,
          ats: card.ats,
        ));
      }
      if (card.tag == TagType.em410X) {
        await comm.setEM410XEmulatorID(
            hexToBytes(card.uid.replaceAll(' ', '')));
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('宸插啓鍏ュ崱妲?${slot + 1}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('写入失败：')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(card.name), actions: [
        IconButton(
          icon: const Icon(Icons.lock_open),
          tooltip: '密钥恢复',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AttackPage()),
          ),
        ),
      ]),
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
                  Text('绫诲瀷: ${card.tag.name}'),
                  Text('SAK: ${card.sak.toRadixString(16).padLeft(2, '0').toUpperCase()}'),
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
          if (card.data.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('鏁版嵁鍧?(${card.data.length})',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (var i = 0; i < card.data.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${i.toString().padLeft(2, '0')}: ${bytesToHexSpace(card.data[i])}',
                          style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}




