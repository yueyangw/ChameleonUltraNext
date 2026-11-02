import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/connector/serial_abstract.dart';
import 'package:chameleon_ultra_next/core/models/slot_info.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/ui/pages/slot_config_page.dart';

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key});

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  List<Chameleon> _devices = const <Chameleon>[];
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    final state = context.read<ChameleonGUIState>();
    final connector = state.connector;
    if (connector == null) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final devices = await connector.availableChameleons(false);
      if (!mounted) return;
      setState(() => _devices = devices);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(Chameleon device) async {
    final state = context.read<ChameleonGUIState>();
    final ok = await state.connectDevice(device);
    if (!ok && mounted) {
      setState(() => _error = state.lastError ?? 'Connection failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ChameleonGUIState>();
    final theme = Theme.of(context);
    final connected = state.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作台'),
        actions: <Widget>[
          IconButton(
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.refresh),
            tooltip: '扫描设备',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: state.refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _ConnectionCard(
              connected: connected,
              busy: state.busy || _scanning,
              error: _error ?? state.lastError,
              devices: _devices,
              onScan: _scan,
              onConnect: _connect,
              onDisconnect: state.disconnect,
              model: state.connector?.device.name ?? 'none',
              port: state.connector?.portName ?? '-',
              firmware: state.firmwareVersion == null
                  ? '-'
                  : (state.firmwareVersion!.legacyProtocol
                      ? 'legacy'
                      : numToVerCode(state.firmwareVersion!.version)),
              battery: state.battery,
            ),
            const SizedBox(height: 16),
            if (!connected)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: <Widget>[
                      Icon(Icons.usb, size: 48, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      const Text('连接 Chameleon 后即可管理 16 个卡槽、轮询与卡包'),
                    ],
                  ),
                ),
              )
            else ...<Widget>[
              _SectionTitle(
                title: '卡槽',
                trailing: Text('${state.slotCount} 个',
                    style: theme.textTheme.bodySmall),
              ),
              const SizedBox(height: 8),
              _SlotGrid(state: state),
              const SizedBox(height: 20),
              _PollingCard(state: state),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connected,
    required this.busy,
    required this.error,
    required this.devices,
    required this.onScan,
    required this.onConnect,
    required this.onDisconnect,
    required this.model,
    required this.port,
    required this.firmware,
    required this.battery,
  });

  final bool connected;
  final bool busy;
  final String? error;
  final List<Chameleon> devices;
  final Future<void> Function() onScan;
  final Future<void> Function(Chameleon) onConnect;
  final Future<void> Function({bool manual}) onDisconnect;
  final String model;
  final String port;
  final String firmware;
  final BatteryCharge? battery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(connected ? Icons.link : Icons.link_off,
                    color: connected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(connected ? '已连接' : '未连接',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: connected
                  ? OutlinedButton.icon(
                      onPressed: busy ? null : () => onDisconnect(manual: true),
                      icon: const Icon(Icons.link_off),
                      label: const Text('断开连接'),
                    )
                  : FilledButton.icon(
                      onPressed: busy ? null : onScan,
                      icon: const Icon(Icons.search),
                      label: Text(busy ? '扫描中...' : '扫描设备'),
                    ),
            ),
            const SizedBox(height: 8),
            if (connected)
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: <Widget>[
                  Text('$model · $port'),
                  Text('固件 $firmware'),
                  if (battery != null) Text('电量 ${battery!.percent}%'),
                ],
              )
            else if (devices.isEmpty)
              Text('未发现设备，请确认 USB/BLE 连接后重试。',
                  style: theme.textTheme.bodySmall)
            else
              Column(
                children: <Widget>[
                  for (final device in devices)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(device.type == ConnectionType.ble
                          ? Icons.bluetooth
                          : Icons.usb),
                      title: Text(device.device.name),
                      subtitle: Text('${device.type.name} · ${device.port}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy ? null : () => onConnect(device),
                    ),
                ],
              ),
            if (error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({required this.state});

  final ChameleonGUIState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = state.slotTypes.length;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (context, index) {
        final active = state.activeSlot == index;
        final enabled = state.enabledSlots[index];
        final type = state.slotTypes[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await state.activateSlot(index);
            if (!context.mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SlotConfigPage(slotIndex: index),
              ),
            );
          },
          onLongPress: () => _showSlotEditor(context, state, index),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: active ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('${index + 1}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (enabled.any())
                      Icon(Icons.circle, size: 8,
                          color: theme.colorScheme.primary),
                  ],
                ),
                const Spacer(),
                Text(
                  type.hf != TagType.unknown ? type.hf.name : 'HF -',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
                Text(
                  type.lf != TagType.unknown ? type.lf.name : 'LF -',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  state.hfNames.length > index && state.hfNames[index].isNotEmpty
                      ? state.hfNames[index]
                      : (state.lfNames.length > index &&
                              state.lfNames[index].isNotEmpty
                          ? state.lfNames[index]
                          : '未命名'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSlotEditor(
      BuildContext context, ChameleonGUIState state, int index) async {
    final nameController = TextEditingController(text: state.hfNames[index]);
    final lfNameController = TextEditingController(text: state.lfNames[index]);
    final hfType = ValueNotifier<TagType>(state.slotTypes[index].hf);
    final lfType = ValueNotifier<TagType>(state.slotTypes[index].lf);
    final hfEnabled = ValueNotifier<bool>(state.enabledSlots[index].hf);
    final lfEnabled = ValueNotifier<bool>(state.enabledSlots[index].lf);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑卡槽 ${index + 1}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ValueListenableBuilder<TagType>(
                valueListenable: hfType,
                builder: (context, value, _) => DropdownButtonFormField<TagType>(
                  value: value,
                  decoration: const InputDecoration(labelText: 'HF 类型'),
                  items: [
                    for (final t in getTagTypesByFrequency(TagFrequency.hf))
                      DropdownMenuItem<TagType>(value: t, child: Text(t.name)),
                  ],
                  onChanged: (v) => hfType.value = v ?? value,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 HF'),
                value: hfEnabled.value,
                onChanged: (v) => hfEnabled.value = v,
              ),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'HF 名称'),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<TagType>(
                valueListenable: lfType,
                builder: (context, value, _) => DropdownButtonFormField<TagType>(
                  value: value,
                  decoration: const InputDecoration(labelText: 'LF 类型'),
                  items: [
                    for (final t in getTagTypesByFrequency(TagFrequency.lf))
                      DropdownMenuItem<TagType>(value: t, child: Text(t.name)),
                  ],
                  onChanged: (v) => lfType.value = v ?? value,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 LF'),
                value: lfEnabled.value,
                onChanged: (v) => lfEnabled.value = v,
              ),
              TextField(
                controller: lfNameController,
                decoration: const InputDecoration(labelText: 'LF 名称'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final comm = state.communicator;
              if (comm != null) {
                await comm.setSlotType(index, hfType.value);
                await comm.setSlotType(index, lfType.value);
                await comm.enableSlot(index, TagFrequency.hf, hfEnabled.value);
                await state.setSlotEnabled(
                    index, TagFrequency.hf, hfEnabled.value);
                await state.setSlotEnabled(
                    index, TagFrequency.lf, lfEnabled.value);
                await state.setSlotName(
                    index, TagFrequency.hf, nameController.text);
                await state.setSlotName(
                    index, TagFrequency.lf, lfNameController.text);
                await state.refreshAll();
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameController.dispose();
    lfNameController.dispose();
    hfType.dispose();
    lfType.dispose();
    hfEnabled.dispose();
    lfEnabled.dispose();
  }
}

class _PollingCard extends StatefulWidget {
  const _PollingCard({required this.state});
  final ChameleonGUIState state;

  @override
  State<_PollingCard> createState() => _PollingCardState();
}

class _PollingCardState extends State<_PollingCard> {
  late PollingConfiguration _config = widget.state.polling.copy();
  late bool _enabled = _config.enabled;
  late double _idle = _config.idleDwellMs.toDouble();
  late double _active = _config.activeDwellMs.toDouble();
  late bool _adaptive = _config.adaptive;
  int _mask = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mask = _config.slotMask == 0
        ? ((1 << widget.state.slotCount) - 1)
        : _config.slotMask;
  }

  Future<void> _apply() async {
    setState(() => _saving = true);
    final c = _config
      ..enabled = _enabled
      ..idleDwellMs = _idle.round()
      ..activeDwellMs = _active.round()
      ..adaptive = _adaptive
      ..slotMask = _mask;
    await widget.state.applyPolling(c);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = widget.state.pollingStatus;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.autorenew),
                const SizedBox(width: 8),
                Text('卡槽轮询', style: theme.textTheme.titleMedium),
                const Spacer(),
                Switch(
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
            if (status != null)
              Text(
                status.running
                    ? '运行中 · 当前卡槽 ${status.currentSlot + 1}'
                    : '已停止',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text('空闲停留 ${_idle.round()} ms'),
            Slider(
              value: _idle.clamp(20, 2000),
              min: 20,
              max: 2000,
              divisions: 99,
              label: '${_idle.round()} ms',
              onChanged: (v) => setState(() => _idle = v),
            ),
            Text('检测到读头时停留 ${_active.round()} ms'),
            Slider(
              value: _active.clamp(50, 5000),
              min: 50,
              max: 5000,
              divisions: 99,
              label: '${_active.round()} ms',
              onChanged: (v) => setState(() => _active = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自适应'),
              subtitle: const Text('无场时快速轮转，有场时延长停留'),
              value: _adaptive,
              onChanged: (v) => setState(() => _adaptive = v),
            ),
            const SizedBox(height: 8),
            Text('参与轮询的卡槽', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (var i = 0; i < widget.state.slotCount; i++)
                  FilterChip(
                    label: Text('${i + 1}'),
                    selected: (_mask & (1 << i)) != 0,
                    onSelected: (value) {
                      setState(() {
                        if (value) {
                          _mask |= 1 << i;
                        } else {
                          _mask &= ~(1 << i);
                        }
                      });
                    },
                  ),
              ],
            ),
            Text(
              '已选择 ${_mask.toRadixString(2).replaceAll('0', '').length} 个卡槽',
              style: theme.textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _apply,
                icon: const Icon(Icons.save),
                label: Text(_saving ? '保存中...' : '应用轮询配置'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
