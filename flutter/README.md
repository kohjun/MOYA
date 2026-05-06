# location_sharing_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.



 1. backend/src/game/plugins/fantasy_wars_artifact/schema.js:14 — configSchema.allowGpsFallbackWithoutBle.default                                                                                                                
  // 현재: default: true   →   운영: default: false                                                                                                                                                                               
  2. backend/src/game/plugins/fantasy_wars_artifact/schema.js:44 — defaultConfig.allowGpsFallbackWithoutBle                                                                                                                     
  // 현재: true   →   운영: false
  3. flutter/lib/features/lobby/presentation/lobby_screen.dart:794 — _FantasyWarsDuelSettings.fromSession 클라이언트 기본값
  // 현재: ?? true   →   운영: ?? false