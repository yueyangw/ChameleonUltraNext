import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/helpers/ndef.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';

class NdefEditorPage extends StatefulWidget {
  const NdefEditorPage({super.key});

  @override
  State<NdefEditorPage> createState() => _NdefEditorPageState();
}

class _NdefEditorPageState extends State<NdefEditorPage> {
  String? _selectedId;
  NdefContainer? _container;
  List<NdefRecord> _records = [];
  final TextEditingController _textController = TextEditingController();
  String? _error;

  void _loadCard(CardSave card) {
    setState(() {
      _selectedId = card.id;
      _container = NdefContainer.detect(card.tag, card.data);
      _error = null;
      if (_container == null) {
        _records = [];
        _textController.text = '';
        return;
      }
      try {
        _records = NdefCodec.decodeMessage(_container!.message);
        final textRecord = _records.where((r) => r.kind == NdefRecordKind.text);
        _textController.text =
            textRecord.isEmpty ? '' : textRecord.first.displayValue;
      } catch (e) {
        _records = [];
        _textRecordError(e);
      }
    });
  }

  void _textRecordError(Object error) {
    _error = '无法解析 NDEF: $error';
  }

  Future<void> _save(CardSave card) async {
    final container = _container;
    if (container == null) return;
    try {
      final message = NdefCodec.encodeMessage([
        NdefRecord.text(_textController.text),
      ]);
      final blocks = card.data.map((block) => Uint8List.fromList(block)).toList();
      container.writeMessage(blocks, message);
      final updated = CardSave(
        id: card.id,
        uid: card.uid,
        name: card.name,
        tag: card.tag,
        sak: card.sak,
        atqa: card.atqa,
        ats: card.ats,
        color: card.color,
        data: blocks,
        extraData: card.extraData,
      );
      final prefs = context.read<SharedPreferencesProvider>();
      final cards = prefs.getCards();
      final index = cards.indexWhere((item) => item.id == card.id);
      if (index >= 0) {
        cards[index] = updated;
      } else {
        cards.add(updated);
      }
      prefs.setCards(cards);
      setState(() {
        _error = null;
        _records = NdefCodec.decodeMessage(message);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NDEF 已写入')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<SharedPreferencesProvider>();
    final cards = prefs.getCards();
    final current = cards.where((card) => card.id == _selectedId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('NDEF 编辑器')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedId,
            decoration: const InputDecoration(
              labelText: '选择卡片',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final card in cards)
                DropdownMenuItem(
                  value: card.id,
                  child: Text(card.name.isEmpty ? card.uid : card.name),
                ),
            ],
            onChanged: (value) {
              final selected =
                  cards.where((card) => card.id == value).firstOrNull;
              if (selected != null) _loadCard(selected);
            },
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
              ),
            ),
          if (_container == null)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('该卡片不支持 NDEF 或未检测到 NDEF 数据'),
              ),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('映射: ${_container!.mappingName}'),
                    Text('容量: ${_container!.capacity} 字节'),
                    Text('当前消息: ${_container!.message.length} 字节'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '文本记录',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: current == null ? null : () => _save(current),
              icon: const Icon(Icons.save),
              label: const Text('写入 NDEF 消息'),
            ),
            const SizedBox(height: 20),
            Text('解析结果', style: Theme.of(context).textTheme.titleMedium),
            for (final record in _records)
              Card(
                child: ListTile(
                  title: Text(record.kind.name),
                  subtitle: SelectableText(record.displayValue),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
