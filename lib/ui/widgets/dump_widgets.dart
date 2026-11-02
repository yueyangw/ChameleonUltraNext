import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/dump_segments.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/dump_analyzer.dart';
import 'package:chameleon_ultra_next/helpers/mifare_classic/general.dart';
import 'package:chameleon_ultra_next/helpers/mifare_ultralight/general.dart';

const TextStyle _mono = TextStyle(fontFamily: 'RobotoMono', fontSize: 13);

/// Number of UID bytes of a saved card ("04 AB CD EF" -> 4, 7 byte UIDs -> 7).
int dumpUidLength(String uid) {
  try {
    return hexToBytes(uid).length == 7 ? 7 : 4;
  } catch (_) {
    return 4;
  }
}

/// Colour key for the roles that appear in [roles].
class DumpLegend extends StatelessWidget {
  const DumpLegend({super.key, required this.roles});

  final Iterable<DumpRole> roles;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final role in roles)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: role.color(brightness),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(role.label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
      ],
    );
  }
}

/// One block rendered as coloured hex bytes, one colour per [DumpSegment].
class DumpBlockRow extends StatelessWidget {
  const DumpBlockRow({
    super.key,
    required this.label,
    required this.data,
    required this.segments,
    this.caption,
    this.dirty = false,
    this.showAscii = true,
    this.onTap,
  });

  final String label;
  final Uint8List data;
  final List<DumpSegment> segments;
  final String? caption;
  final bool dirty;
  final bool showAscii;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final spans = <InlineSpan>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final end = segment.end.clamp(0, data.length);
      final start = segment.start.clamp(0, end);
      if (start == end) continue;
      final text = data.sublist(start, end).map((b) => byteToHex(b)).join(' ');
      final color = segment.role == DumpRole.data
          ? theme.textTheme.bodyMedium?.color
          : segment.role.color(brightness);
      spans.add(
        TextSpan(
          text: i == 0 ? text : ' $text',
          style: TextStyle(
            color: color,
            fontWeight: segment.role == DumpRole.data ? null : FontWeight.bold,
          ),
        ),
      );
    }
    final emptyBlock = data.isEmpty;

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 3,
              color: dirty ? theme.colorScheme.primary : Colors.transparent,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 34,
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: emptyBlock
                        ? Text('（空）', style: _mono.copyWith(color: Colors.grey))
                        : RichText(
                            text: TextSpan(
                              style: _mono.copyWith(
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                              children: spans,
                            ),
                          ),
                  ),
                  if (showAscii && !emptyBlock)
                    Text(
                      bytesToAscii(data),
                      style: _mono.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  if (caption != null)
                    Text(
                      caption!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.edit_outlined,
                size: 16,
                color: theme.colorScheme.outline,
              ),
          ],
        ),
      ),
    );
  }
}

/// Read-only (or tap-to-edit) view of a whole dump with highlighted fields.
class DumpView extends StatelessWidget {
  const DumpView({
    super.key,
    required this.tag,
    required this.uid,
    required this.blocks,
    this.dirty = const <int>{},
    this.onTapBlock,
    this.shrinkWrap = true,
  });

  final TagType tag;
  final String uid;
  final List<Uint8List> blocks;
  final Set<int> dirty;
  final void Function(int index)? onTapBlock;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('该卡片没有 dump 数据'),
      );
    }
    final Widget body = isMifareClassic(tag)
        ? _classic(context)
        : (isMifareUltralight(tag) ? _ultralight(context) : _plain(context));
    return body;
  }

  Set<DumpRole> get _legendRoles {
    if (isMifareClassic(tag)) {
      return {
        DumpRole.uid,
        DumpRole.bcc,
        DumpRole.sak,
        DumpRole.atqa,
        DumpRole.keyA,
        DumpRole.access,
        DumpRole.gpb,
        DumpRole.keyB,
        DumpRole.value,
      };
    }
    if (isMifareUltralight(tag)) {
      return {
        DumpRole.uid,
        DumpRole.bcc,
        DumpRole.lock,
        DumpRole.otp,
        DumpRole.config,
        DumpRole.password,
      };
    }
    return {};
  }

  Widget _legend() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: DumpLegend(roles: _legendRoles),
  );

  Widget _classic(BuildContext context) {
    final uidLength = dumpUidLength(uid);
    final sectorCount = _classicSectorCount();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _legend(),
        for (var sector = 0; sector < sectorCount; sector++)
          _classicSector(context, theme, sector, uidLength),
      ],
    );
  }

  int _classicSectorCount() {
    var count = 0;
    for (var sector = 0; sector < 40; sector++) {
      if (mfClassicGetFirstBlockCountBySector(sector) >= blocks.length) break;
      count++;
    }
    return count;
  }

  Widget _classicSector(
    BuildContext context,
    ThemeData theme,
    int sector,
    int uidLength,
  ) {
    final first = mfClassicGetFirstBlockCountBySector(sector);
    final count = mfClassicGetBlockCountBySector(sector);
    final end = (first + count).clamp(0, blocks.length);
    final trailerIndex = mfClassicGetSectorTrailerBlockBySector(sector);
    final trailer = trailerIndex < blocks.length ? blocks[trailerIndex] : null;
    final trailerOk = trailer != null && trailer.length == 16;
    final accessHex = trailerOk ? bytesToUpperHex(trailer.sublist(6, 9)) : '';
    final accessValid =
        !trailerOk ||
        MifareClassicDumpAnalyzer.accessConditionValues(accessHex) != null;
    final sectorDirty = [for (var i = first; i < end; i++) i]
        .any(dirty.contains);

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        // Without distinct keys all sector tiles share one PageStorage slot
        // and restore each other's expansion state.
        key: PageStorageKey<String>('dump-$uid-sector-$sector'),
        initiallyExpanded: sector == 0 || sectorDirty,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: EdgeInsets.zero,
        title: Row(
          children: [
            Text(
              '扇区 $sector',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (sectorDirty) ...[
              const SizedBox(width: 6),
              Icon(Icons.circle, size: 8, color: theme.colorScheme.primary),
            ],
            if (!accessValid) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.warning_amber,
                size: 16,
                color: theme.colorScheme.error,
              ),
            ],
          ],
        ),
        subtitle: trailerOk
            ? Text(
                'A ${bytesToUpperHex(trailer.sublist(0, 6))}   '
                'B ${bytesToUpperHex(trailer.sublist(10, 16))}',
                style: _mono.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.outline,
                ),
              )
            : null,
        children: [
          for (var i = first; i < end; i++)
            DumpBlockRow(
              label: '$i',
              data: blocks[i],
              segments: classicBlockSegments(
                block: i,
                data: blocks[i],
                uidLength: uidLength,
              ),
              caption: classicBlockCaption(i, uidLength: uidLength),
              dirty: dirty.contains(i),
              onTap: onTapBlock == null ? null : () => onTapBlock!(i),
            ),
          if (trailerOk && !accessValid)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                '访问位的反码校验失败：该扇区在真实卡上会被永久锁死',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ultralight(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _legend(),
        for (var page = 0; page < blocks.length; page++)
          DumpBlockRow(
            label: '$page',
            data: blocks[page],
            segments: ultralightPageSegments(
              tag: tag,
              page: page,
              data: blocks[page],
            ),
            caption: ultralightPageCaption(tag, page),
            dirty: dirty.contains(page),
            onTap: onTapBlock == null ? null : () => onTapBlock!(page),
          ),
      ],
    );
  }

  Widget _plain(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < blocks.length; i++)
          DumpBlockRow(
            label: '$i',
            data: blocks[i],
            segments: [DumpSegment(0, blocks[i].length, DumpRole.data)],
            dirty: dirty.contains(i),
            onTap: onTapBlock == null ? null : () => onTapBlock!(i),
          ),
      ],
    );
  }
}
