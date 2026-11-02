# Chameleon Ultra Next

A from-scratch rewrite of the Chameleon Ultra desktop/mobile client, written in
Flutter. The goal is a new UI on top of the **unchanged** transport and protocol
layer, so the device keeps behaving exactly as before for official clients and
tools.

## Relationship to the upstream GUI

This project is **not** a fork of `GameTec-live/ChameleonUltraGUI`. It is a new
Flutter project that reuses the parts of the upstream client that are not UI:

| Layer | Origin | Status |
|---|---|---|
| `lib/bridge/` (command framing, DFU, firmware flashing protocol) | copied from upstream | kept as-is |
| `lib/connector/` (USB / BLE / native / Android / macOS transports) | copied from upstream | kept as-is |
| `lib/recovery/` (native recovery helpers, ffigen bindings) | copied from upstream | kept as-is |
| `lib/helpers/` (protocol wrappers, slot logic, dump analysis) | copied from upstream | UI-only methods stripped |
| `lib/core/models/card_info.dart` | extracted out of the old `read_card.dart` page | new location |
| `lib/app/` (`app_state.dart`, `app.dart`) | old `main.dart`, split into state + widget | reworked |
| `lib/ui/` | — | **written from scratch** |
| `lib/l10n/` (ARB catalogs) | copied from upstream | translation work continues here |

The whole previous `lib/gui/` tree (~18k lines, 51 files) was deliberately not
carried over: the new UI lives in `lib/ui/`.

Rationale for a new project instead of a fork: the upstream widgets are tightly
coupled to the protocol helpers (the helpers used to import widget/data classes
from `gui/page/read_card.dart`), so a fork would have forced the rewrite to stay
compatible with a UI nobody wants to keep. A fresh project allowed extracting the
handful of data models into `core/` and deleting `gui/` entirely, while still
allowing upstream protocol fixes to be pulled in by hand.

## Layout

```
lib/
  main.dart                bootstrap: load preferences, run the app
  app/
    app.dart               MaterialApp + providers
    app_state.dart         ChameleonGUIState (global state)
  core/
    models/card_info.dart  UI-agnostic card models
  bridge/                  transport framing + DFU (from upstream)
  connector/               platform transports (from upstream)
  recovery/                firmware recovery helpers (from upstream)
  helpers/                 protocol wrappers & dump utilities (from upstream)
  ui/
    theme/app_theme.dart   design tokens
    shell/app_shell.dart   responsive navigation shell
    pages/                 screens (being rebuilt)
  l10n/                    translations
```

## Getting started

The Flutter SDK was not installed on the machine where this project was
scaffolded, so `flutter pub get` has not been run yet and no build has been
verified. First step on a dev machine:

```bash
cd ChameleonUltraNext
flutter pub get
flutter analyze
flutter run -d windows   # or linux / macos / android / ios
```

Platform folders (`android/`, `ios/`, `linux/`, `macos/`, `windows/`, `web/`) were
inherited from the upstream client. The Android `applicationId`/`namespace` and
the desktop window titles were changed to `io.chameleon.ultra.next` and
"Chameleon Ultra Next" so this build can sit next to the official app.

## Status

- [x] transport layer, protocol helper layer, recovery layer carried over
- [x] shared application state separated from `main.dart`
- [x] responsive app shell with a new theme
- [ ] device screen polish (firmware version, slot switching)
- [ ] read / write card flows on top of `ChameleonCommunicator`
- [ ] settings screen backed by `SharedPreferencesProvider`
- [ ] localization keys for all new screens

## License

GPL-3.0, inherited from the upstream Chameleon Ultra GUI. See `LICENSE`.
