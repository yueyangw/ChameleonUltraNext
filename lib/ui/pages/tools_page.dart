import 'package:flutter/material.dart';

import 'package:chameleon_ultra_next/ui/pages/attack_page.dart';
import 'package:chameleon_ultra_next/ui/pages/device_settings_page.dart';
import 'package:chameleon_ultra_next/ui/pages/diagnostics_page.dart';
import 'package:chameleon_ultra_next/ui/pages/dictionary_page.dart';
import 'package:chameleon_ultra_next/ui/pages/dump_editor_page.dart';
import 'package:chameleon_ultra_next/ui/pages/firmware_update_page.dart';
import 'package:chameleon_ultra_next/ui/pages/hf_sniff_page.dart';
import 'package:chameleon_ultra_next/ui/pages/lf_sniff_page.dart';
import 'package:chameleon_ultra_next/ui/pages/logs_page.dart';
import 'package:chameleon_ultra_next/ui/pages/mfkey32_page.dart';
import 'package:chameleon_ultra_next/ui/pages/ndef_editor_page.dart';
import 'package:chameleon_ultra_next/ui/pages/t55xx_page.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('工具')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _section(context, '卡片工具', [
            _tool(
              context,
              icon: Icons.key,
              title: '字典管理',
              subtitle: '导入、新建、导出 MIFARE Classic 密钥字典',
              page: () => const DictionaryPage(),
            ),
            _tool(
              context,
              icon: Icons.lock_open,
              title: 'MIFARE Classic 密钥恢复',
              subtitle: 'Nested / Static Nested / HardNested / Darkside',
              page: () => const AttackPage(),
            ),
            _tool(
              context,
              icon: Icons.memory,
              title: 'MFKey32',
              subtitle: '从检测到的 nonce 计算密钥',
              page: () => const Mfkey32Page(),
            ),
            _tool(
              context,
              icon: Icons.edit_note,
              title: 'Dump 编辑器',
              subtitle: '编辑已保存卡片的块数据',
              page: () => const DumpEditorPage(),
            ),
            _tool(
              context,
              icon: Icons.nfc,
              title: 'NDEF 编辑器',
              subtitle: '读取、编辑并写入 NDEF 消息',
              page: () => const NdefEditorPage(),
            ),
          ]),
          const SizedBox(height: 12),
          _section(context, '嗅探与调试', [
            _tool(
              context,
              icon: Icons.radar,
              title: 'HF 嗅探',
              subtitle: '捕获 13.56 MHz 通信并导出 trace',
              page: () => const HfSniffPage(),
            ),
            _tool(
              context,
              icon: Icons.graphic_eq,
              title: 'LF 嗅探',
              subtitle: '捕获 125 kHz 采样并导出',
              page: () => const LfSniffPage(),
            ),
            _tool(
              context,
              icon: Icons.password,
              title: 'T55xx 密码清理',
              subtitle: '尝试默认密码并清理 T55xx 密码保护',
              page: () => const T55xxPage(),
            ),
            _tool(
              context,
              icon: Icons.receipt_long,
              title: '日志',
              subtitle: '查看设备通讯与工具操作日志',
              page: () => const LogsPage(),
            ),
          ]),
          const SizedBox(height: 12),
          _section(context, '设备', [
            _tool(
              context,
              icon: Icons.tune,
              title: '设备设置',
              subtitle: '动画、按钮、BLE 配对与休眠',
              page: () => const DeviceSettingsPage(),
            ),
            _tool(
              context,
              icon: Icons.system_update,
              title: '固件升级',
              subtitle: '进入 DFU 并刷写固件',
              page: () => const FirmwareUpdatePage(),
            ),
            _tool(
              context,
              icon: Icons.credit_card,
              title: '高级诊断',
              subtitle: 'EMV 扫描与原始 APDU',
              page: () => const DiagnosticsPage(),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _tool(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget Function() page,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(icon, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page()),
      ),
    );
  }
}
