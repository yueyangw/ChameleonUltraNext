# Chameleon Ultra Next

**English** | [简体中文](README.zh-CN.md)

A from-scratch Flutter client for the Chameleon Ultra. It keeps the transport
and protocol layers of the official GUI, so it talks to stock firmware, and
adds a new mobile-first UI built around **16 emulation slots** and
**reader-driven slot polling**, both provided by the companion firmware
[yueyangw/ChameleonUltra](https://github.com/yueyangw/ChameleonUltra).

Download the APK from [Releases](https://github.com/yueyangw/ChameleonUltraNext/releases).
The UI is currently in Simplified Chinese.

## Features

### Workbench

- 16-slot grid: type, nickname and HF/LF state of every slot, enable/disable
  and activate with one tap.
- Slot detail page with HF / LF / Sniff tabs. Each tab lists matching wallet
  cards inline, with download-to-wallet and replace-into-slot actions.
- Sniff tab: per-slot MF1 detection toggle, mfkey32 recovery scoped to the
  slot's UID, and entry points into the HF/LF sniffers.

### Slot polling

- Polling card on the workbench: on/off, slot selection, order, re-read count,
  and an "Advanced" section with every wait of the firmware engine
  (silence after reads, patience after a failed auth, phone re-discovery
  sessions, release after a successful auth, ...). Defaults work for most readers.
- Live status: current slot, phase (idle / field / hold / cooldown), hit count,
  last hit slot, slots skipped after failed auths and the measured reader poll period.
- Works with every firmware generation of the fork: older timer-based engines
  get the fields they understand, unknown bytes are written back unchanged.

### Firmware awareness

On connect the client checks what the firmware supports (16 slots, polling,
reader-driven engine). Missing features are reported once in a dialog and then
as a banner that links to the firmware update page. With stock firmware the
client falls back to 8 slots and hides polling.

### Wallet

- Guided HF read: basic info, dictionary check against every sector, fall back
  to the key-recovery attacks, then dump and save only the unlocked sectors.
- Quick HF read with default keys, LF read.
- Swipe-to-delete, multi-select delete, card detail with the dump viewer.

### Tools

- Dictionary manager: create, import, export and edit MIFARE Classic keys
- MIFARE Classic key recovery and MFKey32 from detected nonces
- Dump editor: UID/keys/access bits/value blocks highlighted per tag type;
  field-aware block editors (block 0 as UID/BCC/SAK/ATQA, sector trailers as
  Key A / access bits / Key B with presets, data blocks as hex + ASCII),
  dirty tracking and undo
- NDEF viewer/editor
- HF 14A sniffer and LF sniffer with trace export
- T55xx password cleaner
- Device settings: animation, button behaviour, BLE pairing, sleep timeout
- Firmware update over USB (DFU zip, integrity-checked before flashing)
- Logs and advanced diagnostics (EMV scan, raw APDU)

## Compatibility

| Firmware | Slots | Polling |
|---|---|---|
| Official RRG firmware | 8 | — |
| Fork, timer-based polling (config v2–v6) | 16 | basic settings |
| Fork, reader-driven polling (config v7, current release) | 16 | full |

Android is the tested platform. The Flutter project also contains iOS, desktop
and web targets inherited from upstream, they are not built or tested.

## Relationship to the upstream GUI

The project is **not** a fork of `GameTec-live/ChameleonUltraGUI`. It reuses the
non-UI layers from upstream and rebuilds the presentation layer:

| Layer | Origin | Status |
|---|---|---|
| `lib/bridge/` | copied from upstream | extended with the 1900+ commands |
| `lib/connector/` | copied from upstream | faster BLE scan/connect, larger MTU |
| `lib/recovery/` | copied from upstream | kept as-is |
| `lib/helpers/` | copied from upstream | UI-only methods stripped, new dump/slot helpers |
| `lib/core/models/` | new | slot info, polling config/status |
| `lib/app/` | reworked | global state |
| `lib/ui/` | written from scratch | Workbench / Wallet / Tools / Settings |

The firmware commands and the polling config layout are documented in the
[firmware README](https://github.com/yueyangw/ChameleonUltra#readme).

## Build

```bash
flutter pub get
flutter gen-l10n
flutter test
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. Without
`android/key.properties` the release build is signed with the debug key.

Do not run `dart format` on the whole tree: the code uses the older formatter
style and a full format rewrites most files.

## Layout

```text
lib/
  main.dart
  app/            app state + MaterialApp
  bridge/         frame transport, command layer
  connector/      USB / BLE / native transports
  core/models/    UI-agnostic card + slot + polling models
  helpers/        protocol wrappers, dump/slot helpers
  recovery/       key recovery (upstream)
  ui/
    shell/        4-tab shell
    pages/        workbench, wallet, read card, tools, settings, ...
    widgets/      dump view, block editors
```
