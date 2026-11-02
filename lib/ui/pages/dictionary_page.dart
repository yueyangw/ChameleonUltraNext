import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/sharedprefsprovider.dart';

/// MIFARE Classic / Ultralight key dictionary manager.
class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<SharedPreferencesProvider>();
    final dictionaries = prefs.getDictionaries();
    return Scaffold(
      appBar: AppBar(
        title: const Text('字典管理'),
        actions: <Widget>[
          IconButton(
            tooltip: '导入字典',
            icon: const Icon(Icons.file_open),
            onPressed: () => _importDictionary(prefs),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editDictionary(prefs),
        icon: const Icon(Icons.add),
        label: const Text('新建字典'),
      ),
      body: dictionaries.isEmpty
          ? const Center(child: Text('还没有字典，点击右下角新建'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: dictionaries.length,
              itemBuilder: (context, index) {
                final dictionary = dictionaries[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: dictionary.color,
                      child: Text(
                        '${dictionary.keys.length}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    title: Text(dictionary.name.isEmpty
                        ? '未命名字典'
                        : dictionary.name),
                    subtitle: Text(
                      '${dictionary.keys.length} 个密钥 · ${dictionary.keyLength} 位',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        switch (value) {
                          case 'view':
                            await _viewDictionary(dictionary);
                            break;
                          case 'edit':
                            await _editDictionary(prefs, dictionary);
                            break;
                          case 'export':
                            await _exportDictionary(dictionary);
                            break;
                          case 'delete':
                            await _deleteDictionary(prefs, dictionary);
                            break;
                        }
                      },
                      itemBuilder: (context) => const <PopupMenuEntry<String>>[
                        PopupMenuItem(value: 'view', child: Text('查看密钥')),
                        PopupMenuItem(value: 'edit', child: Text('编辑')),
                        PopupMenuItem(value: 'export', child: Text('导出')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                    onTap: () => _viewDictionary(dictionary),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _viewDictionary(Dictionary dictionary) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dictionary.name.isEmpty ? '密钥列表' : dictionary.name),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: dictionary.keys.length,
            itemBuilder: (context, index) => ListTile(
              dense: true,
              leading: Text('${index + 1}'),
              title: SelectableText(bytesToHexSpace(dictionary.keys[index])),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _editDictionary(
    SharedPreferencesProvider prefs, [
    Dictionary? existing,
  ]) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final keysController = TextEditingController(
      text: existing == null ? '' : keysToText(existing.keys),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '新建字典' : '编辑字典'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keysController,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: '密钥（每行一个，支持 4/6/8/16 字节）',
                  hintText: 'FFFFFFFFFFFF',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final dictionary = Dictionary.fromString(
      keysController.text,
      name: nameController.text.trim(),
      color: existing?.color ?? Colors.deepOrange,
    );
    dictionary.id = existing?.id ?? dictionary.id;
    if (dictionary.keys.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有识别到有效密钥')),
        );
      }
      return;
    }
    final dictionaries = prefs.getDictionaries();
    final index = dictionaries.indexWhere((item) => item.id == dictionary.id);
    if (index >= 0) {
      dictionaries[index] = dictionary;
    } else {
      dictionaries.add(dictionary);
    }
    prefs.setDictionaries(dictionaries);
    if (mounted) setState(() {});
  }

  Future<void> _importDictionary(SharedPreferencesProvider prefs) async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    if (bytes == null) return;
    final content = utf8.decode(bytes, allowMalformed: true);
    final dictionary = Dictionary.fromString(
      content,
      name: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
    );
    if (dictionary.keys.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未解析到有效密钥')),
        );
      }
      return;
    }
    final dictionaries = prefs.getDictionaries();
    dictionary.id =
        '${dictionary.id}-${DateTime.now().millisecondsSinceEpoch}';
    dictionaries.add(dictionary);
    prefs.setDictionaries(dictionaries);
    if (mounted) setState(() {});
  }

  Future<void> _addDefaultDictionary(SharedPreferencesProvider prefs) async {
    const raw = 'FFFFFFFFFFFF\nA0A1A2A3A4A5\nD3F7D3F7D3F7\n000000000000\nB0B1B2B3B4B5\n4D3A99C351DD\n1A982C7E459A\nAABBCCDDEEFF\nA1B2C3D4E5F6\n123456789ABC\n';
    final dictionary = Dictionary.fromString(raw, name: '内置常用密钥');
    if (dictionary.keys.isEmpty) return;
    final dictionaries = prefs.getDictionaries();
    dictionaries.add(dictionary);
    prefs.setDictionaries(dictionaries);
    if (mounted) setState(() {});
  }
  Future<void> _exportDictionary(Dictionary dictionary) async {
    final path = await FilePicker.saveFile(
      fileName:
          '${dictionary.name.isEmpty ? 'dictionary' : dictionary.name}.dic',
      bytes: utf8.encode(dictionary.toString()),
    );
    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出到 $path')),
      );
    }
  }

  Future<void> _deleteDictionary(
      SharedPreferencesProvider prefs, Dictionary dictionary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除字典'),
        content: Text('确定要删除 ${dictionary.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final dictionaries = prefs.getDictionaries()
      ..removeWhere((item) => item.id == dictionary.id);
    prefs.setDictionaries(dictionaries);
    if (mounted) setState(() {});
  }
}

String bytesToHexSpace(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase();

String keysToText(List<Uint8List> keys) => keys.map(bytesToHexSpace).join('\n');
