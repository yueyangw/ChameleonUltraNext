# Chameleon Ultra Next

[English](README.md) | **简体中文**

从零重写的 Chameleon Ultra Flutter 客户端。它沿用官方 GUI 的传输层和协议层，
因此可以直接连接原厂固件；界面则针对手机重新设计，围绕 **16 个模拟卡槽** 和
**按读卡器行为切换的卡槽轮询** 展开，这两项功能由配套固件
[yueyangw/ChameleonUltra](https://github.com/yueyangw/ChameleonUltra) 提供。

APK 下载见 [Releases](https://github.com/yueyangw/ChameleonUltraNext/releases)。目前界面为简体中文。

## 功能

### 工作台

- 16 卡槽网格：显示每个卡槽的类型、昵称和 HF/LF 状态，一键启用、禁用、激活。
- 卡槽详情页分为 HF / LF / 嗅探 三个标签页。每个标签页直接列出卡包中对应频段的卡片，
  可以把卡槽数据下载到卡包，或用卡包中的卡替换卡槽。
- 嗅探标签页：按卡槽开关 MF1 检测、针对该卡槽 UID 的 mfkey32 密钥恢复，以及 HF/LF 嗅探入口。

### 卡槽轮询

- 工作台上的轮询卡片：开关、卡槽选择、顺序、每张卡重读次数，以及包含固件引擎所有等待参数的
  “高级”区域（读完后静默等待、认证失败后的耐心、手机重复发现保留、认证成功后放手等）。
  默认值适用于大多数读卡器。
- 实时状态：当前卡槽、阶段（空闲 / 有场 / 保持 / 冷却）、命中次数、最后命中卡槽、
  认证失败后被跳过的卡槽，以及实测的读卡器轮询周期。
- 兼容本分支各代固件：旧的计时引擎只下发它能识别的字段，未知字节原样写回。

### 固件适配

连接时客户端会检查固件支持哪些功能（16 卡槽、轮询、按读卡器行为切换的新引擎）。
缺少的功能先弹窗提示一次，之后在工作台顶部显示横幅，点击可进入固件升级页面。
连接原厂固件时客户端回退到 8 个卡槽，并隐藏轮询。

### 卡包

- 引导式 HF 读卡：读取基本信息，对所有扇区做字典检查，失败时转入密钥恢复攻击，
  最后只导出并保存已解锁的扇区。
- 使用默认密钥的快速 HF 读卡，LF 读卡。
- 左滑删除、多选删除，卡片详情页带 dump 查看器。

### 工具

- 字典管理：新建、导入、导出、编辑 MIFARE Classic 密钥
- MIFARE Classic 密钥恢复，以及基于检测到的 nonce 的 MFKey32
- Dump 编辑器：按卡类型高亮 UID / 密钥 / 访问控制位 / 值块；按字段编辑块
  （0 块按 UID/BCC/SAK/ATQA，扇区尾块按 Key A / 访问控制位 / Key B 并提供预设，
  数据块按十六进制 + ASCII），带修改标记与撤销
- NDEF 查看与编辑
- HF 14A 嗅探、LF 嗅探，可导出 trace
- T55xx 密码清理
- 设备设置：动画、按键行为、BLE 配对、休眠时间
- 通过 USB 升级固件（DFU zip，刷写前校验完整性）
- 日志与高级诊断（EMV 扫描、原始 APDU）

## 兼容性

| 固件 | 卡槽 | 轮询 |
|---|---|---|
| RRG 官方固件 | 8 | — |
| 本分支，计时轮询（配置 v2–v6） | 16 | 基础设置 |
| 本分支，按读卡器行为轮询（配置 v7，当前版本） | 16 | 全部 |

目前只在 Android 上测试。Flutter 工程里继承自上游的 iOS、桌面和 Web 目标未构建、未测试。

## 与上游 GUI 的关系

本项目**不是** `GameTec-live/ChameleonUltraGUI` 的分支。它复用了上游的非 UI 层，重写了界面层：

| 层 | 来源 | 状态 |
|---|---|---|
| `lib/bridge/` | 复制自上游 | 增加 1900+ 命令 |
| `lib/connector/` | 复制自上游 | 更快的 BLE 扫描/连接，更大的 MTU |
| `lib/recovery/` | 复制自上游 | 保持原样 |
| `lib/helpers/` | 复制自上游 | 去掉仅 UI 用的方法，新增 dump / 卡槽辅助 |
| `lib/core/models/` | 新增 | 卡槽信息、轮询配置与状态 |
| `lib/app/` | 重写 | 全局状态 |
| `lib/ui/` | 从零编写 | 工作台 / 卡包 / 工具 / 设置 |

固件命令和轮询配置格式见[固件 README](https://github.com/yueyangw/ChameleonUltra/blob/main/README.zh-CN.md)。

## 构建

```bash
flutter pub get
flutter gen-l10n
flutter test
flutter build apk --release
```

APK 输出到 `build/app/outputs/flutter-apk/app-release.apk`。没有 `android/key.properties`
时，release 包使用 debug 密钥签名。

不要对整个工程运行 `dart format`：代码使用旧版格式化风格，全量格式化会改动大部分文件。

## 目录结构

```text
lib/
  main.dart
  app/            应用状态 + MaterialApp
  bridge/         帧传输、命令层
  connector/      USB / BLE / 原生传输
  core/models/    与 UI 无关的卡片、卡槽、轮询模型
  helpers/        协议封装、dump / 卡槽辅助
  recovery/       密钥恢复（上游）
  ui/
    shell/        四标签页外壳
    pages/        工作台、卡包、读卡、工具、设置等
    widgets/      dump 视图、块编辑器
```
