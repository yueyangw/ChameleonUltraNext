import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';

class DumpEditorPage extends StatefulWidget {
  const DumpEditorPage({super.key});

  @override
  State<DumpEditorPage> createState() => _DumpEditorPageState();
}

class _DumpEditorPageState extends State<DumpEditorPage> {
  String? _selectedId;
  final List<TextEditingController> _controllers = [];
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _loadCard(CardSave card) {
    for (final controller in _controllers) {
      controller.dispose();
    }
    _controllers
      ..clear()
      ..addAll(
        card.data.map(
          (block) => TextEditingController(
            text: block.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          ),
        ),
      );
    _selectedId = card.id;
    _error = null;
  }

  void _save(CardSave original) {
    final data = <Uint8List>[];
    for (var i = 0; i < _controllers.length; i++) {
      final text = _controllers[i].text.trim();
      if (text.length.isOdd && text.isNotEmpty) {
        setState(() => _error = '第 ${i + 1} 块不是完整的字节序列');
        return;
      }
      if (text.isEmpty) {
        data.add(Uint8List(0));
        continue;
      }
      if (!RegExp(r'^[0-9A-Fa-f]+$').hasMatch(text)) {
        setState(() => _error = '第 ${i + 1} 块包含非十六进制字符');
        return;
      }
      data.add(hexToBytes(text));
    }
    final updated = CardSave(
      id: original.id,
      uid: original.uid,
      name: original.name,
      tag: original.tag,
      sak: original.sak,
      atqa: original.atqa,
      ats: original.ats,
      color: original.color,
      data: data,
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
    setState(() => _error = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<SharedPreferencesProvider>();
    final cards = prefs.getCards();
    final current = cards.where((card) => card.id == _selectedId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Dump 编辑器')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DropdownButtonFormField<String>(
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
              onChanged: (value) {
                final selected =
                    cards.where((card) => card.id == value).firstOrNull;
                if (selected != null) {
                  _loadCard(selected);
                  setState(() {});
                }
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: current == null
                ? const Center(child: Text('选择一张已保存的卡片'))
                : _controllers.isEmpty
                    ? const Center(child: Text('该卡片没有可编辑的数据'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _controllers.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 48,
                              child: Text(
                                '${index + 1}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _controllers[index],
                                maxLines: 2,
                                style: const TextStyle(
                                  fontFamily: 'RobotoMono',
                                  fontSize: 13,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
          if (current != null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _save(current),
                    icon: const Icon(Icons.save),
                    label: const Text('保存修改'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
