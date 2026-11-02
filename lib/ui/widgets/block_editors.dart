import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chameleon_ultra_next/generated/i18n/app_localizations.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/dump_segments.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/dump_analyzer.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_ultralight/general.dart';
import 'package:chameleon_ultra_next/ui/widgets/dump_widgets.dart';

const TextStyle _mono = TextStyle(fontFamily: 'RobotoMono', fontSize: 15);

/// Opens a field-aware editor for one block / page and returns the edited
/// bytes, or null when cancelled.
///
/// * MIFARE Classic block 0: UID / BCC / SAK / ATQA / manufacturer data
/// * MIFARE Classic sector trailer: Key A, access bits (per block), GPB, Key B
/// * everything else: a byte grid with ASCII preview (and value block helper)
Future<Uint8List?> showBlockEditor(
  BuildContext context, {
  required TagType tag,
  required int index,
  required Uint8List data,
  required String uid,
}) {
  final Widget form;
  final String title;
  if (isMifareClassic(tag)) {
    final sector = mfClassicGetSectorByBlock(index);
    if (index == 0) {
      title = '块 0 · 厂商块';
      form = _Block0Form(data: data, uidLength: dumpUidLength(uid));
    } else if (classicIsTrailer(index)) {
      title = '块 $index · 扇区 $sector 尾块';
      form = _TrailerForm(data: data);
    } else {
      title = '块 $index · 扇区 $sector';
      form = _DataForm(data: data, size: 16, allowValueBlock: true);
    }
  } else if (isMifareUltralight(tag)) {
    final caption = ultralightPageCaption(tag, index);
    title = '页 $index${caption == null ? '' : ' · $caption'}';
    form = _DataForm(data: data, size: 4);
  } else {
    title = '块 $index';
    form = _DataForm(data: data, size: data.isEmpty ? 16 : data.length);
  }

  return showModalBottomSheet<Uint8List>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              form,
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

final _hexFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
  _UpperCaseFormatter(),
];

Uint8List? _parseHex(String text, int bytes) {
  if (text.length != bytes * 2) return null;
  return hexToBytes(text);
}

/// Text field for a fixed number of hex bytes, with live length feedback.
class _HexField extends StatelessWidget {
  const _HexField({
    required this.controller,
    required this.label,
    required this.bytes,
    this.onChanged,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final int bytes;
  final VoidCallback? onChanged;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final length = controller.text.length;
    final complete = length == bytes * 2;
    return TextField(
      controller: controller,
      style: _mono,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        ..._hexFormatters,
        LengthLimitingTextInputFormatter(bytes * 2),
      ],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        counterText: '${length ~/ 1}/${bytes * 2}',
        errorText: complete || length == 0 ? null : '需要 ${bytes * 2} 位十六进制',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (_) => onChanged?.call(),
    );
  }
}

/// A row of single-byte cells; typing two digits moves to the next cell.
class _ByteGrid extends StatefulWidget {
  const _ByteGrid({required this.controllers, this.onChanged});

  final List<TextEditingController> controllers;
  final VoidCallback? onChanged;

  @override
  State<_ByteGrid> createState() => _ByteGridState();
}

class _ByteGridState extends State<_ByteGrid> {
  late final List<FocusNode> _nodes = List.generate(
    widget.controllers.length,
    (_) => FocusNode(),
  );

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 8,
      children: [
        for (var i = 0; i < widget.controllers.length; i++)
          SizedBox(
            width: 46,
            child: Column(
              children: [
                Text(
                  byteToHex(i),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                TextField(
                  controller: widget.controllers[i],
                  focusNode: _nodes[i],
                  style: _mono,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  keyboardType: TextInputType.visiblePassword,
                  inputFormatters: [
                    ..._hexFormatters,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  onTap: () => widget.controllers[i].selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: widget.controllers[i].text.length,
                  ),
                  onChanged: (value) {
                    if (value.length == 2 && i + 1 < _nodes.length) {
                      _nodes[i + 1].requestFocus();
                      final next = widget.controllers[i + 1];
                      next.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: next.text.length,
                      );
                    }
                    widget.onChanged?.call();
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.canSave, required this.onSave, this.onReset});

  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onReset != null)
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.restore),
            label: const Text('还原'),
          ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: canSave ? onSave : null,
          icon: const Icon(Icons.check),
          label: const Text('确定'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Plain data block / page
// ---------------------------------------------------------------------------

class _DataForm extends StatefulWidget {
  const _DataForm({
    required this.data,
    required this.size,
    this.allowValueBlock = false,
  });

  final Uint8List data;
  final int size;
  final bool allowValueBlock;

  @override
  State<_DataForm> createState() => _DataFormState();
}

class _DataFormState extends State<_DataForm> {
  late final List<TextEditingController> _cells;
  final _ascii = TextEditingController();
  final _value = TextEditingController();
  final _address = TextEditingController(text: '00');

  @override
  void initState() {
    super.initState();
    _cells = List.generate(
      widget.size,
      (i) => TextEditingController(
        text: i < widget.data.length ? byteToHex(widget.data[i]) : '00',
      ),
    );
    if (widget.allowValueBlock && classicIsValueBlock(widget.data)) {
      final hex = bytesToUpperHex(widget.data);
      _value.text = '${MifareClassicDumpAnalyzer.valueBlockToInt(hex)}';
      _address.text = byteToHex(
        MifareClassicDumpAnalyzer.valueBlockAddress(hex) ?? 0,
      );
    }
  }

  @override
  void dispose() {
    for (final c in _cells) {
      c.dispose();
    }
    _ascii.dispose();
    _value.dispose();
    _address.dispose();
    super.dispose();
  }

  Uint8List? get _bytes {
    final out = Uint8List(widget.size);
    for (var i = 0; i < widget.size; i++) {
      final text = _cells[i].text;
      if (text.length != 2) return null;
      out[i] = int.parse(text, radix: 16);
    }
    return out;
  }

  void _setAll(Uint8List bytes) {
    for (var i = 0; i < widget.size; i++) {
      _cells[i].text = byteToHex(i < bytes.length ? bytes[i] : 0);
    }
    setState(() {});
  }

  void _applyAscii() {
    final codes = _ascii.text.codeUnits.where((c) => c < 256).toList();
    final bytes = Uint8List(widget.size);
    for (var i = 0; i < widget.size && i < codes.length; i++) {
      bytes[i] = codes[i];
    }
    _setAll(bytes);
  }

  void _applyValue() {
    final value = int.tryParse(_value.text.trim());
    final address = int.tryParse(_address.text, radix: 16) ?? 0;
    if (value == null || value < -0x80000000 || value > 0x7FFFFFFF) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('数值需为 32 位有符号整数')));
      return;
    }
    _setAll(
      hexToBytes(
        MifareClassicDumpAnalyzer.intToValueBlock(value, address & 0xFF),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _bytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Actions(
          canSave: bytes != null,
          onSave: () => Navigator.pop(context, bytes),
          onReset: () => _setAll(widget.data),
        ),
        const SizedBox(height: 8),
        _ByteGrid(controllers: _cells, onChanged: () => setState(() {})),
        const SizedBox(height: 8),
        Text(
          bytes == null ? '有字节尚未填写完整' : 'ASCII  ${bytesToAscii(bytes)}',
          style: _mono.copyWith(
            fontSize: 13,
            color: bytes == null
                ? theme.colorScheme.error
                : theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: const Text('全部 00'),
              onPressed: () => _setAll(Uint8List(widget.size)),
            ),
            ActionChip(
              label: const Text('全部 FF'),
              onPressed: () =>
                  _setAll(Uint8List.fromList(List.filled(widget.size, 0xFF))),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ascii,
                maxLength: widget.size,
                decoration: const InputDecoration(
                  labelText: '按 ASCII 填入',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: _applyAscii, child: const Text('填入')),
          ],
        ),
        if (widget.allowValueBlock) ...[
          const SizedBox(height: 4),
          Text('数值块', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _value,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '数值（有符号 32 位）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _address,
                  style: _mono,
                  inputFormatters: [
                    ..._hexFormatters,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: const InputDecoration(
                    labelText: '地址(HEX)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _applyValue,
                child: const Text('生成'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Block 0
// ---------------------------------------------------------------------------

class _Block0Form extends StatefulWidget {
  const _Block0Form({required this.data, required this.uidLength});

  final Uint8List data;
  final int uidLength;

  @override
  State<_Block0Form> createState() => _Block0FormState();
}

class _Block0FormState extends State<_Block0Form> {
  late final bool _single = widget.uidLength != 7;
  late final TextEditingController _uid;
  late final TextEditingController _bcc;
  late final TextEditingController _sak;
  late final TextEditingController _atqa;
  late final TextEditingController _manufacturer;
  late bool _autoBcc;

  @override
  void initState() {
    super.initState();
    final d = widget.data.length == 16 ? widget.data : Uint8List(16);
    String hex(int a, int b) => bytesToUpperHex(d.sublist(a, b));
    if (_single) {
      _uid = TextEditingController(text: hex(0, 4));
      _bcc = TextEditingController(text: hex(4, 5));
      _sak = TextEditingController(text: hex(5, 6));
      _atqa = TextEditingController(text: hex(6, 8));
      _manufacturer = TextEditingController(text: hex(8, 16));
      _autoBcc = d[4] == classicBcc(d.sublist(0, 4));
    } else {
      _uid = TextEditingController(text: hex(0, 7));
      _bcc = TextEditingController();
      _sak = TextEditingController(text: hex(7, 8));
      _atqa = TextEditingController(text: hex(8, 10));
      _manufacturer = TextEditingController(text: hex(10, 16));
      _autoBcc = false;
    }
  }

  @override
  void dispose() {
    _uid.dispose();
    _bcc.dispose();
    _sak.dispose();
    _atqa.dispose();
    _manufacturer.dispose();
    super.dispose();
  }

  void _syncBcc() {
    if (_single && _autoBcc) {
      final uid = _parseHex(_uid.text, 4);
      if (uid != null) _bcc.text = byteToHex(classicBcc(uid));
    }
    setState(() {});
  }

  Uint8List? get _bytes {
    final uid = _parseHex(_uid.text, _single ? 4 : 7);
    final sak = _parseHex(_sak.text, 1);
    final atqa = _parseHex(_atqa.text, 2);
    final manufacturer = _parseHex(_manufacturer.text, _single ? 8 : 6);
    if (uid == null || sak == null || atqa == null || manufacturer == null) {
      return null;
    }
    if (_single) {
      final bcc = _parseHex(_bcc.text, 1);
      if (bcc == null) return null;
      return Uint8List.fromList([
        ...uid,
        ...bcc,
        ...sak,
        ...atqa,
        ...manufacturer,
      ]);
    }
    return Uint8List.fromList([...uid, ...sak, ...atqa, ...manufacturer]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final uidBytes = _parseHex(_uid.text, _single ? 4 : 7);
    final bccWrong =
        _single &&
        !_autoBcc &&
        uidBytes != null &&
        _parseHex(_bcc.text, 1)?.first != classicBcc(uidBytes);
    final bytes = _bytes;

    Widget colored(DumpRole role, Widget child) => Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: role.color(brightness), width: 3),
        ),
      ),
      padding: const EdgeInsets.only(left: 8),
      child: child,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Actions(
          canSave: bytes != null,
          onSave: () => Navigator.pop(context, bytes),
        ),
        const SizedBox(height: 8),
        colored(
          DumpRole.uid,
          _HexField(
            controller: _uid,
            label: _single ? 'UID（4 字节）' : 'UID（7 字节）',
            bytes: _single ? 4 : 7,
            onChanged: _syncBcc,
          ),
        ),
        if (_single) ...[
          const SizedBox(height: 12),
          colored(
            DumpRole.bcc,
            _HexField(
              controller: _bcc,
              label: 'BCC',
              bytes: 1,
              onChanged: () => setState(() {}),
              helper: bccWrong
                  ? '与 UID 不匹配，正确值为 '
                        '${byteToHex(classicBcc(uidBytes))}'
                  : null,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('根据 UID 自动计算 BCC'),
            value: _autoBcc,
            onChanged: (value) {
              _autoBcc = value;
              _syncBcc();
            },
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: colored(
                DumpRole.sak,
                _HexField(
                  controller: _sak,
                  label: 'SAK',
                  bytes: 1,
                  onChanged: () => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: colored(
                DumpRole.atqa,
                _HexField(
                  controller: _atqa,
                  label: 'ATQA（原始字节）',
                  bytes: 2,
                  onChanged: () => setState(() {}),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        colored(
          DumpRole.manufacturer,
          _HexField(
            controller: _manufacturer,
            label: _single ? '厂商数据（8 字节）' : '厂商数据（6 字节）',
            bytes: _single ? 8 : 6,
            onChanged: () => setState(() {}),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sector trailer
// ---------------------------------------------------------------------------

const List<String> _keyPresets = [
  'FFFFFFFFFFFF',
  'A0A1A2A3A4A5',
  'D3F7D3F7D3F7',
  '000000000000',
];

class _TrailerForm extends StatefulWidget {
  const _TrailerForm({required this.data});

  final Uint8List data;

  @override
  State<_TrailerForm> createState() => _TrailerFormState();
}

class _TrailerFormState extends State<_TrailerForm> {
  late final TextEditingController _keyA;
  late final TextEditingController _keyB;
  late final TextEditingController _gpb;
  late List<int> _conditions; // C1C2C3 of block 0, 1, 2 and the trailer
  bool _accessValid = true;

  @override
  void initState() {
    super.initState();
    final d = widget.data.length == 16 ? widget.data : Uint8List(16);
    _keyA = TextEditingController(text: bytesToUpperHex(d.sublist(0, 6)));
    _keyB = TextEditingController(text: bytesToUpperHex(d.sublist(10, 16)));
    _gpb = TextEditingController(text: byteToHex(d[9]));
    final values = MifareClassicDumpAnalyzer.accessConditionValues(
      bytesToUpperHex(d.sublist(6, 9)),
    );
    _accessValid = values != null;
    _conditions = values ?? const [0, 0, 0, 1];
  }

  @override
  void dispose() {
    _keyA.dispose();
    _keyB.dispose();
    _gpb.dispose();
    super.dispose();
  }

  Uint8List? get _bytes {
    final keyA = _parseHex(_keyA.text, 6);
    final keyB = _parseHex(_keyB.text, 6);
    final gpb = _parseHex(_gpb.text, 1);
    if (keyA == null || keyB == null || gpb == null) return null;
    final access = hexToBytes(
      MifareClassicDumpAnalyzer.encodeAccessConditions(_conditions),
    );
    return Uint8List.fromList([...keyA, ...access, ...gpb, ...keyB]);
  }

  void _presetFor(TextEditingController controller, String value) {
    controller.text = value;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final l10n = AppLocalizations.of(context)!;
    final bytes = _bytes;

    // Human readable meaning of each C1C2C3 value, taken from the analyzer by
    // encoding it for every position and decoding it again.
    String describe(int position, int condition) {
      final values = List<int>.filled(4, 0)..[position] = condition;
      final decoded = MifareClassicDumpAnalyzer.decodeAccessConditions(
        MifareClassicDumpAnalyzer.encodeAccessConditions(values),
        context,
      );
      final access = (decoded['access'] as Map<String, String>?) ?? const {};
      final key = position == 3
          ? l10n.sector_trailer
          : '${l10n.block} $position';
      return access[key] ?? '';
    }

    Widget colored(DumpRole role, Widget child) => Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: role.color(brightness), width: 3),
        ),
      ),
      padding: const EdgeInsets.only(left: 8),
      child: child,
    );

    Widget keyField(
      TextEditingController controller,
      String label,
      DumpRole role,
    ) => colored(
      role,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HexField(
            controller: controller,
            label: label,
            bytes: 6,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (final preset in _keyPresets)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(preset, style: _mono.copyWith(fontSize: 11)),
                  onPressed: () => _presetFor(controller, preset),
                ),
            ],
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Actions(
          canSave: bytes != null,
          onSave: () => Navigator.pop(context, bytes),
          onReset: () {
            final d = widget.data;
            _keyA.text = bytesToUpperHex(d.sublist(0, 6));
            _keyB.text = bytesToUpperHex(d.sublist(10, 16));
            _gpb.text = byteToHex(d[9]);
            final values = MifareClassicDumpAnalyzer.accessConditionValues(
              bytesToUpperHex(d.sublist(6, 9)),
            );
            _accessValid = values != null;
            _conditions = values ?? const [0, 0, 0, 1];
            setState(() {});
          },
        ),
        const SizedBox(height: 8),
        keyField(_keyA, 'Key A（6 字节）', DumpRole.keyA),
        const SizedBox(height: 16),
        colored(
          DumpRole.access,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('访问条件', style: theme.textTheme.titleSmall),
              if (!_accessValid)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '原有访问位的反码校验失败，已按默认条件显示；确定后会写入合法的访问位。',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              for (var position = 0; position < 4; position++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _conditions[position],
                    decoration: InputDecoration(
                      labelText: position == 3
                          ? '扇区尾块 (Key / 访问位)'
                          : '数据块 $position',
                      helperText: describe(position, _conditions[position]),
                      helperMaxLines: 3,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (var c = 0; c < 8; c++)
                        DropdownMenuItem(
                          value: c,
                          child: Text(
                            '${c >> 2 & 1}${c >> 1 & 1}${c & 1}  '
                            '${describe(position, c)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _conditions = List<int>.from(_conditions)
                        ..[position] = value ?? _conditions[position];
                      _accessValid = true;
                    }),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                '字节 6-8：${bytes == null ? '--' : bytesToUpperHex(bytes.sublist(6, 9))}',
                style: _mono.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.outline,
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('出厂默认 (FF0780)'),
                    onPressed: () => setState(() {
                      _conditions = const [0, 0, 0, 1];
                      _accessValid = true;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        colored(
          DumpRole.gpb,
          _HexField(
            controller: _gpb,
            label: 'GPB（用户字节）',
            bytes: 1,
            onChanged: () => setState(() {}),
          ),
        ),
        const SizedBox(height: 16),
        keyField(_keyB, 'Key B（6 字节）', DumpRole.keyB),
      ],
    );
  }
}
