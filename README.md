# Chameleon Ultra Next

A from-scratch Flutter client for the Chameleon Ultra/Lite that keeps the
transport and protocol layer compatible with official clients while adding a
new mobile-first UI, 16 emulation slots and configurable slot polling.

## Status

- 4-tab shell: Workbench / Wallet / Tools / Settings
- 16 slot grid with enable/ disable and activation
- polling configuration panel (idle/active dwell, adaptive, keep-awake)
- wallet with saved cards and read-card flows
- key-recovery entry backed by the upstream recovery library
- debug APK build: `flutter build apk --debug`
- release APK build: `flutter build apk --release`

## Relationship to the upstream GUI

The project is **not** a fork of `GameTec-live/ChameleonUltraGUI`. It reuses the
non-UI layers from upstream and rebuilds the presentation layer:

| Layer | Origin | Status |
|---|---|---|
| `lib/bridge/` | copied from upstream | extended with V2 commands |
| `lib/connector/` | copied from upstream | kept as-is |
| `lib/recovery/` | copied from upstream | kept as-is |
| `lib/helpers/` | copied from upstream | UI-only methods stripped |
| `lib/core/models/` | new / extended | `slot_info.dart` |
| `lib/app/` | reworked | global state |
| `lib/ui/` | written from scratch | Workbench/Wallet/Tools/Settings |

## Firmware extensions

See [docs/custom/implementation.md](../../docs/custom/implementation.md) for
the 16-slot migration and polling command payloads. The legacy 8-slot commands
are unchanged; new clients use `1900..1904`.

## Build

```bash
cd ChameleonUltraNext
flutter pub get
flutter gen-l10n
flutter analyze
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.
Firmware is built from `ChameleonUltra-firmware/firmware`; the DFU package is
written to `firmware/objects/ultra-dfu-app.zip`.

## Layout

```text
lib/
  main.dart
  app/            app state + MaterialApp
  bridge/         frame transport, command layer
  connector/      USB / BLE / native transports
  core/models/    UI-agnostic card + slot models
  helpers/        protocol wrappers, dump helpers
  ui/
    shell/app_shell.dart
    pages/workbench_page.dart
    pages/wallet_page.dart
    pages/attack_page.dart
    pages/tools_page.dart
    pages/settings_page.dart
```

## Implemented tools

- Dictionary manager: create, import, export and edit MIFARE Classic keys
- HF 14A sniffer: capture, annotate and import/export traces
- LF sniffer: sample capture, Manchester decoding and export
- T55xx password cleaner with dictionary-driven password search
- MFKey32 detection and key calculation
- Dump editor with per-block hex editing
- NDEF viewer/editor and message re-encoding
- Device settings: animation, button behavior, BLE pairing, sleep timeout
- Log viewer with debug-log switch
- Advanced diagnostics: EMV scan and raw APDU exchange