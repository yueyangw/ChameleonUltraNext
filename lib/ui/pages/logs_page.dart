import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleon_ultra_next/sharedprefsprovider.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<SharedPreferencesProvider>();
    final lines = prefs.getLogLines();
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: prefs.touch,
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              prefs.clearLogLines();
              prefs.touch();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('调试日志'),
            subtitle: const Text('记录设备通讯与工具操作'),
            value: prefs.isDebugLogging(),
            onChanged: (value) {
              prefs.setDebugLogging(value);
              prefs.touch();
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: lines.isEmpty
                ? const Center(child: Text('暂无日志'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: lines.length,
                    itemBuilder: (context, index) => SelectableText(
                      lines[index],
                      style: const TextStyle(
                        fontFamily: 'RobotoMono',
                        fontSize: 11,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
