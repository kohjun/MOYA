# Graph Report - /work/raw  (2026-04-18)

## Corpus Check
- 99 files · ~66,880 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1009 nodes · 1391 edges · 34 communities detected
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 134 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]

## God Nodes (most connected - your core abstractions)
1. `package:flutter/material.dart` - 39 edges
2. `package:flutter_riverpod/flutter_riverpod.dart` - 29 edges
3. `get()` - 28 edges
4. `query()` - 27 edges
5. `Room` - 25 edges
6. `dart:async` - 17 edges
7. `Peer` - 16 edges
8. `startGameForSession()` - 13 edges
9. `../game_mode_plugin.dart` - 13 edges
10. `VoteSession` - 12 edges

## Surprising Connections (you probably didn't know these)
- `startGameForSession()` --calls--> `getMediaServer()`  [INFERRED]
  /work/raw/backend/src/game/startGameService.js → /work/raw/backend/src/media/MediaServer.js
- `createFastifyApp()` --calls--> `register()`  [INFERRED]
  /work/raw/backend/src/server.js → /work/raw/backend/src/services/authService.js
- `createFastifyApp()` --calls--> `get()`  [INFERRED]
  /work/raw/backend/src/server.js → /work/raw/backend/src/game/GamePluginRegistry.js
- `startServer()` --calls--> `connectRedis()`  [INFERRED]
  /work/raw/backend/src/server.js → /work/raw/backend/src/config/redis.js
- `startServer()` --calls--> `startSessionCleaner()`  [INFERRED]
  /work/raw/backend/src/server.js → /work/raw/backend/src/cron/sessionCleaner.js

## Communities

### Community 0 - "Community 0"
Cohesion: 0.05
Nodes (15): authRoutes(), get(), geofenceRoutes(), ensureMediaRoomForSocket(), normalizeGameState(), saveGameState(), syncMediaRoomState(), KillCooldownManager (+7 more)

### Community 1 - "Community 1"
Cohesion: 0.03
Nodes (69): app.dart, app_initialization_service.dart, ../../../core/services/app_initialization_service.dart, ../../../core/services/fcm_service.dart, dart:async, dart:convert, dart:io, dart:ui (+61 more)

### Community 2 - "Community 2"
Cohesion: 0.03
Nodes (65): ../../auth/data/auth_repository.dart, ../../../core/network/api_client.dart, ../../../core/router/app_router.dart, ../data/auth_repository.dart, ../data/session_repository.dart, package:flutter_riverpod/flutter_riverpod.dart, package:go_router/go_router.dart, ../services/socket_service.dart (+57 more)

### Community 3 - "Community 3"
Cohesion: 0.03
Nodes (61): dart:math, ../data/game_models.dart, minigame_registry.dart, ../minigames/minigame_wrapper_screen.dart, package:mobile_scanner/mobile_scanner.dart, ../../providers/game_provider.dart, build, _buildBottomActions (+53 more)

### Community 4 - "Community 4"
Cohesion: 0.05
Nodes (35): notifyChannelProducerAvailability(), getMemberUserId(), VoteSession, VoteSystem, _controllerForGameEvent, disconnect, dispose, emit (+27 more)

### Community 5 - "Community 5"
Cohesion: 0.04
Nodes (54): ../../../features/auth/data/auth_repository.dart, ../../features/auth/presentation/login_screen.dart, ../../features/auth/presentation/register_screen.dart, ../../features/game/presentation/game_main_screen.dart, ../../features/game/presentation/game_result_screen.dart, ../../features/game/presentation/game_role_screen.dart, ../../features/game/presentation/session_info_screen.dart, ../../features/geofence/presentation/geofence_screen.dart (+46 more)

### Community 6 - "Community 6"
Cohesion: 0.04
Nodes (51): build, _buildActionArea, _buildCompletedBadge, _buildCompletionMethod, _buildDefaultSection, _buildHeader, _buildMiniGameSection, _buildMissionHeader (+43 more)

### Community 7 - "Community 7"
Cohesion: 0.04
Nodes (50): game_meeting_screen.dart, ../../map/data/map_session_provider.dart, qr_scanner_screen.dart, session_info_screen.dart, widgets/ai_chat_panel.dart, widgets/mission_list_sheet.dart, _AiChatBar, AnimatedContainer (+42 more)

### Community 8 - "Community 8"
Cohesion: 0.08
Nodes (40): createRefreshToken(), getUserById(), login(), logout(), register(), rotateRefreshToken(), query(), withTransaction() (+32 more)

### Community 9 - "Community 9"
Cohesion: 0.07
Nodes (35): ../game_mode_plugin.dart, ../game_module.dart, ../modules/bounds_module.dart, ../modules/kill_module.dart, ../modules/location_mission_module.dart, ../modules/meeting_module.dart, ../modules/qr_mission_module.dart, ../modules/sabotage_module.dart (+27 more)

### Community 10 - "Community 10"
Cohesion: 0.04
Nodes (44): ../../../core/services/background_service.dart, ../../../core/services/location_service.dart, ../../../core/services/mediasoup_audio_service.dart, ../../../core/services/socket_service.dart, ../../geofence/data/geofence_repository.dart, ../../home/data/session_repository.dart, package:geolocator/geolocator.dart, ../presentation/map_session_models.dart (+36 more)

### Community 11 - "Community 11"
Cohesion: 0.05
Nodes (43): ../../game/presentation/playable_area_painter_screen.dart, package:share_plus/share_plus.dart, ../providers/lobby_provider.dart, AnimatedContainer, _AppBarMicToggle, _AppBarMicToggleState, _AudioCheckSection, _AudioCheckSectionState (+35 more)

### Community 12 - "Community 12"
Cohesion: 0.05
Nodes (39): ../../../core/services/sound_service.dart, ../../firebase_options.dart, package:audioplayers/audioplayers.dart, package:firebase_core/firebase_core.dart, package:flutter/foundation.dart, package:flutter_naver_map/flutter_naver_map.dart, package:maps_toolkit/maps_toolkit.dart, package:wakelock_plus/wakelock_plus.dart (+31 more)

### Community 13 - "Community 13"
Cohesion: 0.05
Nodes (38): card_swipe_game.dart, package:flame/collisions.dart, package:flame/components.dart, package:flame/events.dart, package:flame/game.dart, wire_fix_game.dart, backgroundColor, CardComponent (+30 more)

### Community 14 - "Community 14"
Cohesion: 0.09
Nodes (26): addHistory(), ask(), askWithModel(), askWithRetry(), buildAskFailure(), createGenerativeModel(), getHistory(), isGeminiCredentialError() (+18 more)

### Community 15 - "Community 15"
Cohesion: 0.06
Nodes (30): ../data/history_repository.dart, package:intl/intl.dart, AppInitializationService, build, Center, Container, dispose, _FilterPanel (+22 more)

### Community 16 - "Community 16"
Cohesion: 0.1
Nodes (14): EventBus, on(), createSocketServer(), buildListenInfos(), createMediasoupWorkers(), getMediaServer(), getWorkerCount(), initializeMediaServer() (+6 more)

### Community 17 - "Community 17"
Cohesion: 0.07
Nodes (26): package:mediasoup_client_flutter/mediasoup_client_flutter.dart, package:permission_handler/permission_handler.dart, _bindSocketStreams, _closeMediaState, _consumeExistingProducers, _consumePeer, _createRecvTransport, _createSendTransport (+18 more)

### Community 18 - "Community 18"
Cohesion: 0.1
Nodes (20): ../../../game/data/game_models.dart, ../../../game/providers/game_provider.dart, AIChatPanel, _AIChatPanelState, build, _buildLogCard, Center, Container (+12 more)

### Community 19 - "Community 19"
Cohesion: 0.11
Nodes (14): GeminiProvider, AppSettings, build, _confirmLogout, copyWith, Divider, _save, Scaffold (+6 more)

### Community 20 - "Community 20"
Cohesion: 0.22
Nodes (16): onGameStart(), assignMissions(), clearSession(), completeMission(), generateMissionPool(), getMissions(), getProgress(), getProgressBar() (+8 more)

### Community 21 - "Community 21"
Cohesion: 0.14
Nodes (13): AmongUsGameState, AnimalPoint, ChatLog, CoinPoint, copyWith, fromTemplateTitle, fromWire, GameMission (+5 more)

### Community 22 - "Community 22"
Cohesion: 0.25
Nodes (7): package:dio/dio.dart, package:flutter_secure_storage/flutter_secure_storage.dart, ApiClient, clearTokens, Function, _refreshAccessToken, saveTokens

### Community 23 - "Community 23"
Cohesion: 0.33
Nodes (3): embedText(), main(), getEmbeddableChunks()

### Community 24 - "Community 24"
Cohesion: 0.5
Nodes (0): 

### Community 25 - "Community 25"
Cohesion: 1.0
Nodes (0): 

### Community 26 - "Community 26"
Cohesion: 1.0
Nodes (0): 

### Community 27 - "Community 27"
Cohesion: 1.0
Nodes (0): 

### Community 28 - "Community 28"
Cohesion: 1.0
Nodes (0): 

### Community 29 - "Community 29"
Cohesion: 1.0
Nodes (0): 

### Community 30 - "Community 30"
Cohesion: 1.0
Nodes (0): 

### Community 31 - "Community 31"
Cohesion: 1.0
Nodes (0): 

### Community 32 - "Community 32"
Cohesion: 1.0
Nodes (0): 

### Community 33 - "Community 33"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **639 isolated node(s):** `EventBus`, `LocationApp`, `build`, `DefaultFirebaseOptions`, `UnsupportedError` (+634 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 25`** (1 nodes): `prompt.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 26`** (1 nodes): `common.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 27`** (1 nodes): `crew.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 28`** (1 nodes): `faq.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 29`** (1 nodes): `impostor.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 30`** (1 nodes): `items.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 31`** (1 nodes): `migrate.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 32`** (1 nodes): `AmongUsPlugin.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 33`** (1 nodes): `index.js`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter/material.dart` connect `Community 9` to `Community 1`, `Community 2`, `Community 3`, `Community 5`, `Community 6`, `Community 7`, `Community 10`, `Community 11`, `Community 13`, `Community 15`, `Community 18`, `Community 19`?**
  _High betweenness centrality (0.287) - this node is a cross-community bridge._
- **Why does `emit` connect `Community 4` to `Community 0`, `Community 20`?**
  _High betweenness centrality (0.249) - this node is a cross-community bridge._
- **Why does `dart:async` connect `Community 1` to `Community 4`, `Community 6`, `Community 7`, `Community 10`, `Community 11`, `Community 12`, `Community 13`, `Community 15`, `Community 17`?**
  _High betweenness centrality (0.235) - this node is a cross-community bridge._
- **Are the 27 inferred relationships involving `get()` (e.g. with `createFastifyApp()` and `ask()`) actually correct?**
  _`get()` has 27 INFERRED edges - model-reasoned connections that need verification._
- **Are the 25 inferred relationships involving `query()` (e.g. with `register()` and `login()`) actually correct?**
  _`query()` has 25 INFERRED edges - model-reasoned connections that need verification._
- **What connects `EventBus`, `LocationApp`, `build` to the rest of the system?**
  _639 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.05 - nodes in this community are weakly interconnected._