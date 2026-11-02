import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/app/app_state.dart';
import 'package:chameleon_ultra_next/helpers/general.dart';
import 'package:chameleon_ultra_next/sharedprefsprovider.dart';
import 'package:chameleon_ultra_next/ui/pages/device_settings_page.dart';
import 'package:chameleon_ultra_next/ui/pages/logs_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<SharedPreferencesProvider>();
    final state = context.watch<ChameleonGUIState>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _Section(title: '外观', children: [
            ListTile(
              title: const Text('主题模式'),
              trailing: DropdownButton<ThemeMode>(
                value: prefs.getTheme(),
                onChanged: (v) {
                  if (v == null) return;
                  prefs.setTheme(v);
                  prefs.touch();
                },
                items: const [
                  DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
                ],
              ),
            ),
            ListTile(
              title: const Text('主题色'),
              trailing: DropdownButton<int>(
                value: prefs.getThemeColorIndex(),
                onChanged: (v) {
                  if (v == null) return;
                  prefs.setThemeColor(v);
                  prefs.touch();
                },
                items: [
                  for (var i = 0; i < 8; i++)
                    DropdownMenuItem(value: i, child: Text('颜色 ${i + 1}')),
                ],
              ),
            ),
          ]),
          _Section(title: '客户端', children: [
            SwitchListTile(
              title: const Text('自动扫描'),
              value: prefs.getAutoScanEnabled(),
              onChanged: (v) {
                prefs.setAutoScanEnabled(v);
                prefs.touch();
              },
            ),
            SwitchListTile(
              title: const Text('自动连接第一个设备'),
              value: prefs.getAutoConnectFirstFoundDevice(),
              onChanged: (v) {
                prefs.setAutoConnectFirstFoundDevice(v);
                prefs.touch();
              },
            ),
            SwitchListTile(
              title: const Text('调试日志'),
              subtitle: const Text('记录设备通讯与工具操作'),
              value: prefs.isDebugLogging(),
              onChanged: (v) {
                prefs.setDebugLogging(v);
                prefs.touch();
              },
            ),
            ListTile(
              title: const Text('界面语言'),
              subtitle: Text(prefs.getLocale().toLanguageTag()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showLanguage(context, prefs),
            ),
          ]),
          _Section(title: '设备', children: [
            ListTile(
              title: const Text('设备信息'),
              subtitle: Text(state.connected
                  ? '${state.connector?.device.name} · ${state.connector?.portName}'
                  : '未连接'),
            ),
            ListTile(
              title: const Text('固件版本'),
              subtitle: Text(state.firmwareVersion == null
                  ? '-'
                  : (state.firmwareVersion!.legacyProtocol
                      ? 'legacy'
                      : numToVerCode(state.firmwareVersion!.version))),
            ),
            ListTile(
              title: const Text('设备设置'),
              subtitle: const Text('动画、按钮、BLE 配对与休眠'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DeviceSettingsPage(),
                ),
              ),
            ),
            ListTile(
              title: const Text('日志'),
              subtitle: const Text('查看设备通讯记录'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LogsPage()),
              ),
            ),
          ]),
          _Section(title: '关于', children: [
            const ListTile(
              title: Text('Chameleon Ultra Next'),
              subtitle: Text('GPL-3.0 · 自定义固件客户端'),
            ),
            ListTile(
              title: const Text('安全声明'),
              subtitle: const Text('仅用于你拥有或获授权的卡片与设备'),
              trailing: Icon(Icons.warning_amber,
                  color: Theme.of(context).colorScheme.error),
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => const AlertDialog(
                  title: Text('安全声明'),
                  content: Text('本工具包含写卡与密钥恢复功能。请仅在拥有合法授权的设备与卡片上使用。\n\n伪造、克隆或未授权访问他人卡片可能违法。'),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _showLanguage(
      BuildContext context, SharedPreferencesProvider prefs) async {
    final locales = [
      const Locale('zh'),
      const Locale('en'),
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('界面语言'),
        children: [
          for (final locale in locales)
            SimpleDialogOption(
              onPressed: () {
                prefs.setLocale(locale);
                prefs.touch();
                Navigator.pop(context);
              },
              child: Text(locale.languageCode == 'zh' ? '中文' : 'English'),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
