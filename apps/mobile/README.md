# apps/mobile — Fadhkur Mobile App

High-performance, Arabic-first mobile application built with **Flutter**, **Riverpod**, and **Material 3** for **Fadhkur (فذكر)**.

## Architecture
- **Composition Root**: `AppServices` initialized before `runApp()`, providing clean dependency injection via Riverpod overrides.
- **Visual Identity**: `FadhkurTheme` implementing Deep Indigo (`#243B6B`), Teal (`#2E9E9E`), Copper Accent (`#C77955`), and Pearl/Night background tokens.
- **Brand Mark**: Dynamic, custom-painted geometric open Quran book with acoustic soundwave and recitation arc.
- **RTL & Localization**: Arabic-first with full English fallback support.
- **Playback**: Integrated background audio service architecture using `just_audio` and `audio_session`.

## Running the App
```bash
flutter pub get
flutter run
```
