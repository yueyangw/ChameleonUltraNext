import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/helpers/definitions.dart';

class DeviceSettingsPage extends StatefulWidget {
  const DeviceSettingsPage({super.key});

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  bool _loading = true;
  String? _error;
  AnimationSetting _animation = AnimationSetting.full;
  ButtonConfig _aPress = ButtonConfig.disable;
  ButtonConfig _bPress = ButtonConfig.disable;
  ButtonConfig _aLong = ButtonConfig.disable;
  ButtonConfig _bLong = ButtonConfig.disable;
  bool _pairing = false;
  final TextEditingController _sleepController = TextEditingController();
  final TextEditingController _thresholdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _sleepController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final comm = context.read<ChameleonGUIState>().communicator;
    if (comm == null) {
      setState(() {
        _loading = false;
        _error = '未连接设备';
      });
      return;
    }
    try {
      final settings = await comm.getDeviceSettings();
      // The settings blob has no room for these two; ask for them directly.
      int? sleepTimeout = settings.wakeTimeSeconds;
      int? longPress = settings.longPressThreshold;
      try {
        sleepTimeout = await comm.getSleepTimeout();
      } catch (_) {}
      try {
        longPress = await comm.getLongPressThreshold();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _animation = settings.animation;
        _aPress = settings.aPress;
        _bPress = settings.bPress;
        _aLong = settings.aLongPress;
        _bLong = settings.bLongPress;
        _pairing = settings.pairingEnabled;
        _sleepController.text = '${sleepTimeout ?? ''}';
        _thresholdController.text = '${longPress ?? ''}';
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    final comm = context.read<ChameleonGUIState>().communicator;
    if (comm == null) return;
    setState(() => _loading = true);
    try {
      await comm.setAnimationMode(_animation);
      await comm.setButtonConfig(ButtonType.a, _aPress);
      await comm.setButtonConfig(ButtonType.b, _bPress);
      await comm.setLongButtonConfig(ButtonType.a, _aLong);
      await comm.setLongButtonConfig(ButtonType.b, _bLong);
      await comm.setBLEPairEnabled(_pairing);
      final sleep = int.tryParse(_sleepController.text.trim());
      if (sleep != null) await comm.setSleepTimeout(sleep);
      final threshold = int.tryParse(_thresholdController.text.trim());
      if (threshold != null) await comm.setLongPressThreshold(threshold);
      // Without this the firmware keeps the changes in RAM only and falls back
      // to the stored values (e.g. full animation) after the next reset.
      await comm.saveSettings();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设备设置已保存')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ChameleonGUIState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备设置'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!state.connected)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.link_off),
                      title: Text('未连接'),
                      subtitle: Text('请先连接设备再修改设置'),
                    ),
                  ),
                if (_error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(_error!),
                    ),
                  ),
                DropdownButtonFormField<AnimationSetting>(
                  initialValue: _animation,
                  decoration: const InputDecoration(
                    labelText: '灯光动画',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final value in AnimationSetting.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(_animationLabel(value)),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _animation = value ?? _animation),
                ),
                const SizedBox(height: 12),
                _buttonConfig(
                  'A 键短按',
                  _aPress,
                  (value) => setState(() => _aPress = value),
                ),
                const SizedBox(height: 12),
                _buttonConfig(
                  'B 键短按',
                  _bPress,
                  (value) => setState(() => _bPress = value),
                ),
                const SizedBox(height: 12),
                _buttonConfig(
                  'A 键长按',
                  _aLong,
                  (value) => setState(() => _aLong = value),
                ),
                const SizedBox(height: 12),
                _buttonConfig(
                  'B 键长按',
                  _bLong,
                  (value) => setState(() => _bLong = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _sleepController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '休眠超时（秒，0 表示不自动休眠）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _thresholdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '长按阈值（毫秒）',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  title: const Text('允许 BLE 配对'),
                  subtitle: const Text('关闭后已有绑定仍可使用'),
                  value: _pairing,
                  onChanged: (value) => setState(() => _pairing = value),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: state.connected ? _save : null,
                  icon: const Icon(Icons.save),
                  label: const Text('保存到设备'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: state.connected
                      ? () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('恢复出厂设置'),
                              content: const Text('这会清除设备上的所有槽位与设置，确定继续？'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('继续'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            try {
                              await state.communicator!.factoryReset();
                              await state.refreshAll();
                            } catch (e) {
                              if (mounted)
                                setState(() => _error = e.toString());
                            }
                          }
                        }
                      : null,
                  icon: const Icon(Icons.restore),
                  label: const Text('恢复出厂设置'),
                ),
              ],
            ),
    );
  }

  String _animationLabel(AnimationSetting value) {
    switch (value) {
      case AnimationSetting.full:
        return '完整动画';
      case AnimationSetting.minimal:
        return '精简动画';
      case AnimationSetting.none:
        return '关闭动画';
      case AnimationSetting.symmetric:
        return '对称动画';
    }
  }

  String _buttonLabel(ButtonConfig value) {
    switch (value) {
      case ButtonConfig.disable:
        return '禁用';
      case ButtonConfig.cycleForward:
        return '向后切换卡槽';
      case ButtonConfig.cycleBackward:
        return '向前切换卡槽';
      case ButtonConfig.cloneUID:
        return '克隆 UID';
      case ButtonConfig.chargeStatus:
        return '显示充电状态';
    }
  }

  Widget _buttonConfig(
    String label,
    ButtonConfig value,
    ValueChanged<ButtonConfig> onChanged,
  ) {
    return DropdownButtonFormField<ButtonConfig>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final item in ButtonConfig.values)
          DropdownMenuItem(value: item, child: Text(_buttonLabel(item))),
      ],
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }
}
