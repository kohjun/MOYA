# Project Full Report

Generated: 2026-04-19  
Scope: `C:\MOYA` project, based on `graphify-out/graph.json`, `graphify-out/GRAPH_REPORT.md`, and key source entry points.

## Executive Summary

This project is a real-time location-based multiplayer game platform with an Among Us-style game loop layered on top of a location sharing and voice communication stack.

- Backend stack: Fastify, Socket.IO, Redis, PostgreSQL, mediasoup, Firebase Admin, Gemini integration.
- Mobile stack: Flutter, Riverpod, GoRouter, Dio, Socket.IO client, mediasoup client, Naver Map, Flame minigames.
- Primary product shape: session creation, lobby flow, live location/game map, role-based gameplay, meeting/voting, mission completion, voice routing, AI announcements/chat.
- Architectural center of gravity: Flutter game UI and providers dominate the graph, while backend game orchestration and media routing act as the server-side core.

## Graph Snapshot

- Files analyzed: 99
- Approximate corpus size: 66,880 words
- Total nodes: 1009
- Total edges: 1391
- Communities detected: 34
- Edge extraction quality: 90% extracted, 10% inferred, 0% ambiguous
- Relation mix: 588 `defines`, 334 `imports`, 249 `calls`, 140 `contains`, 80 `method`
- Node distribution: 749 Flutter-side nodes, 260 backend-side nodes

Interpretation:

- The mobile client is the dominant implementation surface.
- The graph is dense enough to support impact analysis and subsystem navigation.
- Inferred edges are concentrated in backend orchestration code and should be treated as hints, not facts, until verified in code.

## System Overview

The system has four major layers:

- Client application layer: Flutter screens, providers, routing, and device services.
- Game domain layer: roles, missions, meetings, sabotage, QR and minigame interactions.
- Real-time communication layer: Socket.IO event transport plus mediasoup voice channels.
- Persistence and platform services: PostgreSQL, Redis, FCM, auth, geofencing, session cleanup.

Key entry points:

- Backend entry: `backend/src/server.js`
- Game start orchestration: `backend/src/game/startGameService.js`
- Socket event hub: `backend/src/websocket/index.js`
- Flutter app entry: `flutter/lib/app.dart`
- Flutter route composition: `flutter/lib/core/router/app_router.dart`
- Game state client core: `flutter/lib/features/game/providers/game_provider.dart`
- Main game screen: `flutter/lib/features/game/presentation/game_main_screen.dart`

## Backend Architecture

### 1. API and Process Boot

`backend/src/server.js` builds the server process around Fastify and then attaches the real-time stack.

- Registers auth, session, and geofence routes.
- Validates DB connectivity with health checks.
- Connects Redis before opening the app.
- Initializes mediasoup workers before the Socket.IO layer.
- Starts a session cleaner cron after boot.

This makes the backend effectively a hybrid service:

- REST for authentication and session management.
- WebSocket for live game, location, mission, meeting, and voice flows.

### 2. Real-Time Transport and Game Event Hub

`backend/src/websocket/index.js` is the central nervous system of the runtime.

- Defines client-server event protocol.
- Handles session join/leave and live status updates.
- Bridges location, SOS, geofence, meeting, mission, sabotage, and AI events.
- Connects Redis Streams adapter for Socket.IO scaling.
- Wires mediasoup signaling and game state synchronization.

This file is not just a transport adapter. It is a runtime coordinator that binds session state, game rules, notifications, media state, and live gameplay.

### 3. Game Domain Services

The backend game core is concentrated under `backend/src/game`.

- `startGameService.js`: validates host and player count, assigns impostors, initializes state in Redis, syncs media room state, emits role and start events, and assigns missions.
- `MissionSystem.js`: mission pool generation, assignment, per-player mission retrieval, shared progress calculation, and completion handling.
- `VoteSystem.js`: meeting and voting lifecycle.
- `KillCooldownManager.js`: impostor kill pacing and rule enforcement.
- `GamePluginRegistry.js` and `AmongUsPlugin.js`: plugin-style game behavior composition.
- `EventBus.js`: internal event dispatch for game subsystems.

The graph suggests the game subsystem is cohesive enough to be identifiable as a standalone product domain, but the websocket hub still owns too much orchestration.

### 4. Voice and Media Layer

The voice model is more advanced than a simple mute/unmute implementation.

- `backend/src/media/MediaServer.js` initializes mediasoup workers and room management.
- `backend/src/media/Room.js` maintains peers, channel membership, alive/dead media gating, forced muting, and meeting voice transitions.
- `backend/src/media/Peer.js` represents peer-level media state.

`Room.js` is one of the strongest backend hubs in the graph. That matches the code: voice behavior is deeply entangled with game state.

### 5. Data and Platform Services

Backend dependencies imply the following platform responsibilities:

- PostgreSQL for durable domain data such as users, sessions, membership, and geofences.
- Redis for ephemeral game state, session/game TTL state, adapter transport, and coordination.
- Firebase Admin for push-style alerts.
- Gemini integration through `backend/src/ai/AIDirector.js`.

The top backend inferred-edge sources are:

- `media/Room.js`
- `services/sessionService.js`
- `services/authService.js`
- `game/VoteSystem.js`
- `game/startGameService.js`

This indicates the most complex backend logic is concentrated in media, session orchestration, auth, and live game coordination.

## Flutter Client Architecture

### 1. App Shell and Navigation

The Flutter application starts in `flutter/lib/app.dart` and uses Riverpod plus GoRouter.

- `app.dart` constructs `MaterialApp.router`.
- `core/router/app_router.dart` gates access based on auth state.
- Main route surfaces include login, register, home, lobby, game, history, geofence, settings, and member management.

This is a conventional shell, but the graph shows routing is still important because it bridges auth, session, and game experiences.

### 2. Cross-Cutting Services

`flutter/lib/core/services` contains the client-side infrastructure layer.

- `socket_service.dart`
- `mediasoup_audio_service.dart`
- `location_service.dart`
- `background_service.dart`
- `fcm_service.dart`
- `notification_service.dart`
- `sound_service.dart`
- `app_initialization_service.dart`

This layer is doing the heavy lifting for device capabilities and live connectivity. The graph ranks `socket_service.dart` and `mediasoup_audio_service.dart` as two of the most connected internal client nodes.

### 3. Feature Modules

`flutter/lib/features` is organized by domain:

- `auth`
- `home`
- `lobby`
- `game`
- `map`
- `geofence`
- `history`
- `session`
- `settings`

This is a clean feature-first structure. The graph shows the game feature dominates overall complexity, which is consistent with the codebase intent.

## Game Feature Architecture

The game feature is the operational center of the mobile app.

Key files and responsibilities:

- `features/game/providers/game_provider.dart`: state coordination, server event ingestion, mission normalization, role state, progress state, and minigame linkage.
- `features/game/data/game_models.dart`: canonical game entities such as `AmongUsGameState`, `GameMission`, `CoinPoint`, `AnimalPoint`, `ChatLog`.
- `features/game/presentation/game_main_screen.dart`: main runtime UI shell for gameplay.
- `features/game/presentation/game_meeting_screen.dart`: meeting and vote flow.
- `features/game/presentation/widgets/mission_list_sheet.dart`: player mission view and entry to mission interactions.
- `features/game/presentation/minigames/*`: Flame-based minigames and registry/wrapper.
- `features/game/presentation/modules/*`: mission, sabotage, kill, bounds, meeting, QR, NFC interaction modules.
- `features/game/presentation/modes/*`: alternate game-mode plugin implementations.

Graph evidence:

- `game_main_screen.dart` is the single highest-degree internal node in the entire graph.
- `session_info_screen.dart`, `game_provider.dart`, `game_meeting_screen.dart`, `ai_chat_panel.dart`, and `game_mode_plugin.dart` are all major hubs.
- Communities 3, 6, 7, 13, 18, 20, and 21 all cluster around game presentation, mission UX, minigames, or game models.

Interpretation:

- The game client is implemented as a modular UI with plugins and modules, but the runtime still converges heavily on `game_main_screen.dart` and `game_provider.dart`.
- This is workable, but these two files are likely long-term maintenance hotspots.

## Real-Time Game Loop

The core gameplay path appears to be:

- Session is created and users join through standard app/session flow.
- Host starts a game.
- Backend `startGameForSession()` validates state and assigns roles.
- Backend mission system assigns role-aware missions.
- Backend websocket layer emits game start, role, mission, and progress events.
- Flutter `game_provider.dart` ingests and normalizes those events.
- `game_main_screen.dart` and mission widgets render state and route users into map actions, QR actions, or minigames.
- Meeting, elimination, sabotage, and AI events continue over the same real-time channel.
- mediasoup room state changes based on meeting/game voice rules.

This is a unified live-game architecture rather than a set of isolated mini features.

## Key Hotspots

### Highest-impact internal hubs

- `flutter/lib/features/game/presentation/game_main_screen.dart`
- `flutter/lib/features/game/presentation/session_info_screen.dart`
- `flutter/lib/features/lobby/presentation/lobby_screen.dart`
- `flutter/lib/features/history/presentation/history_screen.dart`
- `flutter/lib/core/services/socket_service.dart`
- `flutter/lib/features/game/providers/game_provider.dart`
- `flutter/lib/core/services/mediasoup_audio_service.dart`
- `backend/src/game/GamePluginRegistry.js`
- `backend/src/config/database.js`
- `backend/src/media/Room.js`

### Architectural significance

- Client complexity is UI-state heavy.
- Backend complexity is orchestration heavy.
- Voice/media is not peripheral. It is a first-class game mechanic.
- Mission and meeting logic are central to product behavior, not add-ons.

## Notable Graph Findings

### Strong findings

- `startGameForSession()` is directly tied to mission assignment, role assignment, game-state initialization, and media-room synchronization.
- `Room` and `Peer` are core abstractions, confirming that voice behavior is part of game logic.
- `game_models.dart` and `game_provider.dart` form the normalization boundary between backend events and Flutter UI.
- `game_main_screen.dart` is acting as a composition root for many game subfeatures.

### Inferred connections worth validating

- `startGameForSession()` to `getMediaServer()`
- `createFastifyApp()` to auth/game registry internals
- `startServer()` to Redis connection and session cleanup

These are plausible and mostly consistent with the source, but inferred edges should not be treated as authoritative without code confirmation.

## Knowledge Gaps and Noise

The graph report calls out:

- 639 isolated or weakly connected nodes
- Several one-node communities such as `prompt.js`, `common.js`, `crew.js`, `faq.js`, `impostor.js`, `items.js`, `migrate.js`, `AmongUsPlugin.js`, `index.js`

Interpretation:

- Some of this is normal graph noise from utility files or content files.
- Some of it is due to extraction limits on UI `build` methods and generic names like `get()` or `query()`.
- Some of it suggests documentation and naming could be improved for discoverability.

## Risks

### 1. Game UI concentration risk

`game_main_screen.dart` appears to be the most connected internal node. This usually means future changes to gameplay, missions, overlays, meeting prompts, and interactions are likely to converge in one file.

### 2. Provider orchestration risk

`game_provider.dart` is a critical translation layer between backend events and presentation state. Regressions here can break multiple game surfaces at once.

### 3. Websocket hub complexity

`backend/src/websocket/index.js` mixes protocol, state syncing, notification triggers, and game runtime coordination. That increases the chance of subtle side effects.

### 4. Media-game coupling

The room voice model is intentionally coupled to alive/dead/meeting state. That is correct for gameplay, but it also means media changes can create gameplay regressions and vice versa.

## Recommended Next Steps

- Extract a dedicated architecture report for the game subsystem only.
- Split `game_main_screen.dart` by runtime area: HUD, mission actions, overlays, meeting triggers, and minigame entry.
- Split backend websocket handling by domain: session, game, media, and alerts.
- Add explicit documentation for event contracts between backend and Flutter.
- Add a machine-readable event schema for Socket.IO payloads.
- Re-run `graphify update ./raw` after major refactors and compare graph deltas over time.

## Bottom Line

This is not a simple location-sharing app anymore. It is a multiplayer, role-based, real-time game system with:

- mobile-first gameplay UX
- backend game orchestration
- stateful voice-channel control
- live mission and meeting mechanics
- AI-assisted game messaging

The codebase already contains the right domain boundaries to support further growth, but the current hotspots suggest the next scaling step should focus on reducing orchestration concentration in the main game screen, provider, and websocket hub.
