# Graph Report - C:/MOYA  (2026-04-28)

## Corpus Check
- Large corpus: 589 files · ~331,661 words. Semantic extraction will be expensive (many Claude tokens). Consider running on a subfolder, or use --no-semantic to run AST-only.

## Summary
- 4313 nodes · 8000 edges · 88 communities detected
- Extraction: 79% EXTRACTED · 21% INFERRED · 0% AMBIGUOUS · INFERRED: 1676 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Flutter App Shell|Flutter App Shell]]
- [[_COMMUNITY_E2EE Web Worker (compiled)|E2EE Web Worker (compiled)]]
- [[_COMMUNITY_Android Audio Devices|Android Audio Devices]]
- [[_COMMUNITY_Audio Switch & CC Map Projection|Audio Switch & CC Map Projection]]
- [[_COMMUNITY_WebRTC Codec Examples|WebRTC Codec Examples]]
- [[_COMMUNITY_Audio Processing & Auth|Audio Processing & Auth]]
- [[_COMMUNITY_Backend AI & Game Loop|Backend AI & Game Loop]]
- [[_COMMUNITY_BLE Presence Service|BLE Presence Service]]
- [[_COMMUNITY_Android Audio Track|Android Audio Track]]
- [[_COMMUNITY_WebRTC Example UI|WebRTC Example UI]]
- [[_COMMUNITY_Android Audio Switch Manager|Android Audio Switch Manager]]
- [[_COMMUNITY_Flutter Plugin Lifecycle|Flutter Plugin Lifecycle]]
- [[_COMMUNITY_Backend Config & Services|Backend Config & Services]]
- [[_COMMUNITY_MOYA Platform Docs|MOYA Platform Docs]]
- [[_COMMUNITY_Duel System Backend|Duel System Backend]]
- [[_COMMUNITY_macOS WebRTC Peer Connection|macOS WebRTC Peer Connection]]
- [[_COMMUNITY_AI Director (RAG)|AI Director (RAG)]]
- [[_COMMUNITY_Desktop Plugin Registrant|Desktop Plugin Registrant]]
- [[_COMMUNITY_Color Chaser Backend|Color Chaser Backend]]
- [[_COMMUNITY_Color Chaser Flutter|Color Chaser Flutter]]
- [[_COMMUNITY_Fantasy Wars Duel UI|Fantasy Wars Duel UI]]
- [[_COMMUNITY_macOS Media Stream|macOS Media Stream]]
- [[_COMMUNITY_macOS Frame Cryptor (E2EE)|macOS Frame Cryptor (E2EE)]]
- [[_COMMUNITY_WebRTC Tests|WebRTC Tests]]
- [[_COMMUNITY_Android Video Renderer|Android Video Renderer]]
- [[_COMMUNITY_Mediasoup RTP Parameters|Mediasoup RTP Parameters]]
- [[_COMMUNITY_macOS Data Channel|macOS Data Channel]]
- [[_COMMUNITY_Fantasy Wars HUD|Fantasy Wars HUD]]
- [[_COMMUNITY_Simulcast Video Encoder|Simulcast Video Encoder]]
- [[_COMMUNITY_Flutter Desktop Codecs|Flutter Desktop Codecs]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 71|Community 71]]
- [[_COMMUNITY_Community 72|Community 72]]
- [[_COMMUNITY_Community 73|Community 73]]
- [[_COMMUNITY_Community 76|Community 76]]
- [[_COMMUNITY_Community 77|Community 77]]
- [[_COMMUNITY_Community 78|Community 78]]
- [[_COMMUNITY_Community 79|Community 79]]
- [[_COMMUNITY_Community 80|Community 80]]
- [[_COMMUNITY_Community 81|Community 81]]
- [[_COMMUNITY_Community 82|Community 82]]
- [[_COMMUNITY_Community 83|Community 83]]
- [[_COMMUNITY_Community 84|Community 84]]
- [[_COMMUNITY_Community 86|Community 86]]
- [[_COMMUNITY_Community 97|Community 97]]
- [[_COMMUNITY_Community 119|Community 119]]
- [[_COMMUNITY_Community 120|Community 120]]
- [[_COMMUNITY_Community 121|Community 121]]
- [[_COMMUNITY_Community 227|Community 227]]
- [[_COMMUNITY_Community 228|Community 228]]

## God Nodes (most connected - your core abstractions)
1. `get` - 222 edges
2. `HandleMethodCall()` - 84 edges
3. `call$1()` - 81 edges
4. `MethodCallHandlerImpl` - 76 edges
5. `PeerConnectionObserver` - 74 edges
6. `call$0()` - 60 edges
7. `wrapException()` - 53 edges
8. `FlutterWebRTCPlugin` - 50 edges
9. `package:flutter/material.dart` - 47 edges
10. `dart:async` - 47 edges

## Surprising Connections (you probably didn't know these)
- `MOYA Real-time Location AI Game Platform` --semantically_similar_to--> `MOYA Project Overview`  [INFERRED] [semantically similar]
  CLAUDE.md → README.md
- `startServer()` --calls--> `connectRedis()`  [INFERRED]
  backend\src\server.js → backend\src\config\redis.js
- `PeerConnectionObserversForId()` --calls--> `get`  [INFERRED]
  flutter\packages\flutter_webrtc\common\cpp\src\flutter_webrtc_base.cc → flutter\lib\features\game\presentation\game_ui_plugin.dart
- `HandleMethodCall()` --calls--> `restartIce`  [INFERRED]
  flutter\packages\flutter_webrtc\common\cpp\src\flutter_webrtc.cc → flutter\packages\mediasoup_client_flutter\lib\src\transport.dart
- `HandleMethodCall()` --calls--> `value`  [INFERRED]
  flutter\packages\flutter_webrtc\common\cpp\src\flutter_webrtc.cc → flutter\packages\mediasoup_client_flutter\lib\src\rtp_parameters.dart

## Hyperedges (group relationships)
- **Hub File Refactor Targets (oversized files)** — readme_hub_game_main_screen, readme_hub_game_provider, readme_hub_room_js [EXTRACTED 0.95]
- **Websocket Layered Separation Pattern (hub + protocol + runtime + handlers)** — readme_websocket_index_hub, readme_socket_protocol, readme_socket_runtime, readme_websocket_handlers [EXTRACTED 0.95]
- **Fantasy Wars Role Roster** — fwtp_role_warrior, fwtp_role_priest, fwtp_role_mage, fwtp_role_ranger, fwtp_role_rogue [EXTRACTED 1.00]

## Communities

### Community 0 - "Flutter App Shell"
Cohesion: 0.0
Nodes (462): app.dart, app_initialization_service.dart, ../../auth/data/auth_repository.dart, build, LocationApp, ApiClient, clearTokens, Function (+454 more)

### Community 1 - "E2EE Web Worker (compiled)"
Cohesion: 0.01
Nodes (465): add$1(), add$1$ax(), addAll$1(), _addAllFromArray$1(), _addEventError$0(), _addHashTableEntry$3(), _addListener$1(), _addPending$1() (+457 more)

### Community 2 - "Android Audio Devices"
Cohesion: 0.02
Nodes (44): fromAudioDevice(), fromTypeName(), RecordSamplesReadyCallbackAdapter, get, contains, name, enabled, initialize (+36 more)

### Community 3 - "Audio Switch & CC Map Projection"
Cohesion: 0.01
Nodes (231): PermissionLock, CcMapProjection, Offset, _projectX, _projectY, toPixel, AlertDialog, build (+223 more)

### Community 4 - "WebRTC Codec Examples"
Cohesion: 0.01
Nodes (237): AdmSample, build, CodecCapability, CodecCapabilitySelector, setCapabilities, setCodecPreferences, setPreferredCodec, AudioControl (+229 more)

### Community 5 - "Audio Processing & Auth"
Cohesion: 0.02
Nodes (185): sdp, thumbnail, EventChannel, close, Ssrc, send, fl_texture_proxy_copy_pixels(), fl_texture_proxy_new() (+177 more)

### Community 6 - "Backend AI & Game Loop"
Cohesion: 0.02
Nodes (121): fwOnGameEnd(), emit, getSession, pause, resume, activateNextControlPoint(), cancelStaleMissions(), expireActiveControlPointIfNeeded() (+113 more)

### Community 7 - "BLE Presence Service"
Cohesion: 0.01
Nodes (195): _availabilityMessage, BlePresenceSighting, BlePresenceStatus, _bytesToHex, Duration, _emitStatus, _ensureStatusSubscription, FantasyWarsBlePresenceService (+187 more)

### Community 8 - "Android Audio Track"
Cohesion: 0.02
Nodes (107): LocalAudioTrack, AudioTrack, build, Card, Color, Column, Container, DecoratedBox (+99 more)

### Community 9 - "WebRTC Example UI"
Cohesion: 0.02
Nodes (108): build, _buildRow, createState, _initItems, initState, ListBody, main, MaterialApp (+100 more)

### Community 10 - "Android Audio Switch Manager"
Cohesion: 0.03
Nodes (19): AudioSwitchManager, AudioUtils, WebRtcAudioTrackUtils, AudioSamplesInterceptor, submit, run, DeviceOrientationManager, BootReceiver (+11 more)

### Community 11 - "Flutter Plugin Lifecycle"
Cohesion: 0.04
Nodes (22): ActivityAware, stop, DefaultLifecycleObserver, flutter(), SetMessageHandler(), SetMethodCallHandler(), FlutterPlugin, Fragment (+14 more)

### Community 12 - "Backend Config & Services"
Cohesion: 0.06
Nodes (59): parse, ScalabilityMode, query(), withTransaction(), connectRedis(), delCache(), delPattern(), getCache() (+51 more)

### Community 13 - "MOYA Platform Docs"
Cohesion: 0.03
Nodes (68): MOYA Real-time Location AI Game Platform, AI RAG Rule Provider, Flutter location_sharing_app Starter README, AmongUsPlugin (live, legacy), Capability: faction (fantasy_wars), Capability: item, Capability: kill, Capability: mission (+60 more)

### Community 14 - "Duel System Backend"
Cohesion: 0.06
Nodes (27): buildScreen, GameUiPlugin, GameUiPluginRegistry, minPlayersFor, register, resolve, DuelService, buildBlackjackDeck() (+19 more)

### Community 15 - "macOS WebRTC Peer Connection"
Cohesion: 0.04
Nodes (51): FlutterWebRTCPlugin, -findCodecCapabilitycodecparameters, -parseJavaScriptConstraintsintoWebRTCConstraints, -parseMediaConstraints, -peerConnectionAddICECandidatepeerConnectionresult, -peerConnectionClose, -peerConnectionCreateAnswerpeerConnectionresult, -peerConnectionCreateOfferpeerConnectionresult (+43 more)

### Community 16 - "AI Director (RAG)"
Cohesion: 0.06
Nodes (31): addHistory(), ask(), askWithModel(), askWithRetry(), buildAskFailure(), createGenerativeModel(), fwOnCpCaptured(), fwOnDuelDraw() (+23 more)

### Community 17 - "Desktop Plugin Registrant"
Cohesion: 0.06
Nodes (33): RegisterPlugins(), ClearPlugins(), GetInstance(), OnRegistrarDestroyed(), PluginRegistrar(), FlutterWindow(), OnCreate(), OnDestroy() (+25 more)

### Community 18 - "Color Chaser Backend"
Cohesion: 0.06
Nodes (33): applyElimination(), processTagAttempt(), pruneCandidatePools(), unlockHintForPlayer(), startMission(), submitMission(), pickColorsForPlayers(), sanitizeBodyProfile() (+25 more)

### Community 19 - "Color Chaser Flutter"
Cohesion: 0.04
Nodes (46): CcCpLifecycleEvent, ColorChaserNotifier, dispose, _emitCpEvent, _handleGameOver, _handleStateUpdate, _handleTagEvent, refreshState (+38 more)

### Community 20 - "Fantasy Wars Duel UI"
Cohesion: 0.06
Nodes (33): AnimatedBuilder, build, _cardLabel, Color, ColoredBox, dispose, _finish, GestureDetector (+25 more)

### Community 21 - "macOS Media Stream"
Cohesion: 0.07
Nodes (30): AVCaptureDevice, -positionString, FlutterWebRTCPlugin, -captureDevices, -createLocalMediaStream, -defaultAudioConstraints, -defaultMediaStreamConstraints, -defaultVideoConstraints (+22 more)

### Community 22 - "macOS Frame Cryptor (E2EE)"
Cohesion: 0.07
Nodes (29): FlutterWebRTCPlugin, -frameCryptordidStateChangeWithParticipantIdwithState, -frameCryptorDisposeresult, -frameCryptorFactoryCreateFrameCryptorresult, -frameCryptorFactoryCreateKeyProviderresult, -frameCryptorGetEnabledresult, -frameCryptorGetKeyIndexresult, -frameCryptorSetEnabledresult (+21 more)

### Community 23 - "WebRTC Tests"
Cohesion: 0.06
Nodes (25): main, main, main, main, MapSessionState, _mapState, main, emitConnection (+17 more)

### Community 24 - "Android Video Renderer"
Cohesion: 0.09
Nodes (4): EglRenderer, EglUtils, FlutterRTCVideoRenderer, SurfaceTextureRenderer

### Community 25 - "Mediasoup RTP Parameters"
Cohesion: 0.07
Nodes (28): assign, CodecParameters, copy, ExtendedRtpCodec, ExtendedRtpHeaderExtension, fromMap, fromString, RtcpFeedback (+20 more)

### Community 26 - "macOS Data Channel"
Cohesion: 0.08
Nodes (23): FlutterWebRTCPlugin, -createDataChannellabelconfigmessengerresult, -dataChannelClosedataChannelId, -dataChanneldidChangeBufferedAmount, -dataChannelDidChangeState, -dataChanneldidReceiveMessageWithBuffer, -dataChannelGetBufferedAmountdataChannelIdresult, -dataChannelSenddataChannelIddatatype (+15 more)

### Community 27 - "Fantasy Wars HUD"
Cohesion: 0.08
Nodes (24): _ActionChip, build, CircularProgressIndicator, Container, _CpChip, _dungeonLabel, FwActionDock, FwChallengingIndicator (+16 more)

### Community 28 - "Simulcast Video Encoder"
Cohesion: 0.09
Nodes (4): FallbackFactory, SimulcastVideoEncoderFactoryWrapper, StreamEncoderWrapper, StreamEncoderWrapperFactory

### Community 29 - "Flutter Desktop Codecs"
Cohesion: 0.17
Nodes (16): flutter(), flutter(), DecodeMessageInternal(), DecodeMethodCallInternal(), EncodedTypeForValue(), EncodeErrorEnvelopeInternal(), EncodeMessageInternal(), EncodeMethodCallInternal() (+8 more)

### Community 30 - "Community 30"
Cohesion: 0.11
Nodes (16): FlutterWebRTCPlugin, -applyExposureModeonDevice, -applyFocusModeonDevice, -currentDevice, -findDeviceForPosition, -getCGPointForCoordsWithOrientationxy, -mediaStreamTrackHasTorchresult, -mediaStreamTrackSetExposureModeexposureModeresult (+8 more)

### Community 31 - "Community 31"
Cohesion: 0.11
Nodes (16): FlutterWebRTCPlugin, -buildDesktopSourcesListWithTypesforceReloadresult, -didDesktopSourceAdded, -didDesktopSourceNameChanged, -didDesktopSourceRemoved, -didDesktopSourceThumbnailChanged, -didSourceCaptureError, -didSourceCapturePaused (+8 more)

### Community 32 - "Community 32"
Cohesion: 0.13
Nodes (14): FlutterRTCVideoRenderer, -copyI420ToCVPixelBufferwithFrame, -copyPixelBuffer, -correctRotationwithRotation, -dispose, -initWithTextureRegistrymessenger, -onCancelWithArguments, -onListenWithArgumentseventSink (+6 more)

### Community 33 - "Community 33"
Cohesion: 0.12
Nodes (7): fl_register_plugins(), flutter_web_r_t_c_plugin_register_with_registrar(), FlutterWebRTCPluginImpl, main(), my_application_activate(), my_application_dispose(), my_application_new()

### Community 34 - "Community 34"
Cohesion: 0.13
Nodes (14): FlutterSocketConnectionFrameReader, -didCaptureVideoFramewithOrientation, -initWithDelegate, -readBytesFromStream, -startCaptureWithConnection, -stopCapture, -streamhandleEvent, Message (+6 more)

### Community 35 - "Community 35"
Cohesion: 0.15
Nodes (10): AudioProcessingAdapter, -addAudioRenderer, -addProcessing, -audioProcessingInitializeWithSampleRatechannels, -audioProcessingProcess, -audioProcessingRelease, -init, -removeAudioRenderer (+2 more)

### Community 36 - "Community 36"
Cohesion: 0.17
Nodes (9): AudioUtils, -audioSessionCategoryFromString, -audioSessionModeFromString, -deactiveRtcAudioSession, -ensureAudioSessionWithRecording, -selectAudioInput, -setAppleAudioConfiguration, -setSpeakerphoneOn (+1 more)

### Community 37 - "Community 37"
Cohesion: 0.18
Nodes (2): AudioProcessingAdapter, ExternalAudioFrameProcessing

### Community 38 - "Community 38"
Cohesion: 0.18
Nodes (8): LocalVideoTrack, -addProcessing, -addRenderer, -initWithTrack, -initWithTrackvideoProcessing, -removeProcessing, -removeRenderer, -track

### Community 39 - "Community 39"
Cohesion: 0.33
Nodes (7): averagePoint(), buildControlPoints(), closestTo(), computeBounds(), normalizeGeoList(), pickSpreadPoints(), pointInPolygon()

### Community 40 - "Community 40"
Cohesion: 0.2
Nodes (7): AudioManager, -addLocalAudioRenderer, -addRemoteAudioSink, -init, -removeLocalAudioRenderer, -removeRemoteAudioSink, -sharedInstance

### Community 41 - "Community 41"
Cohesion: 0.2
Nodes (7): LocalAudioTrack, -addProcessing, -addRenderer, -initWithTrack, -removeProcessing, -removeRenderer, -track

### Community 42 - "Community 42"
Cohesion: 0.2
Nodes (7): VideoProcessingAdapter, -addProcessing, -capturerdidCaptureVideoFrame, -initWithRTCVideoSource, -removeProcessing, -setSize, -source

### Community 43 - "Community 43"
Cohesion: 0.22
Nodes (1): SdkCapabilityChecker

### Community 44 - "Community 44"
Cohesion: 0.22
Nodes (6): FlutterWebRTCPlugin, -createDataPacketCryptorresult, -dataPacketCryptorDecryptresult, -dataPacketCryptorDisposeresult, -dataPacketCryptorEncryptresult, -handleDataPacketCryptorMethodCallresult

### Community 45 - "Community 45"
Cohesion: 0.22
Nodes (6): FlutterRPScreenRecorder, -handleSourceBuffersampleType, -initWithDelegate, -startCapture, -stopCapture, -stopCaptureWithCompletionHandler

### Community 46 - "Community 46"
Cohesion: 0.22
Nodes (8): FlutterRTCVideoPlatformView, -fromFrameRotation, -initWithFrame, -layoutSubviews, -renderFrame, -sampleBufferFromPixelBuffer, -setSize, -toCVPixelBuffer

### Community 47 - "Community 47"
Cohesion: 0.22
Nodes (8): FlutterRTCVideoPlatformViewController, -initWithMessengerviewIdentifierframe, -onCancelWithArguments, -onListenWithArgumentseventSink, -renderFrame, -setSize, -setVideoTrack, -view

### Community 48 - "Community 48"
Cohesion: 0.22
Nodes (8): FlutterSocketConnection, -close, -initWithFilePath, -openWithStreamDelegate, -scheduleStreams, -setupNetworkThread, -setupSocketWithFileAtPath, -unscheduleStreams

### Community 49 - "Community 49"
Cohesion: 0.25
Nodes (3): EventChannelProxyImpl, MethodCallProxyImpl, MethodResultProxyImpl

### Community 50 - "Community 50"
Cohesion: 0.25
Nodes (5): FlutterRTCFrameCapturer, -convertToCVPixelBuffer, -initWithTracktoPathresult, -renderFrame, -setSize

### Community 51 - "Community 51"
Cohesion: 0.25
Nodes (6): FlutterRTCMediaRecorder, -initialize, -initWithVideoTrackaudioTrackoutputFile, -renderFrame, -setSize, -stop

### Community 52 - "Community 52"
Cohesion: 0.33
Nodes (3): getEmbeddableChunks(), embedText(), main()

### Community 53 - "Community 53"
Cohesion: 0.33
Nodes (2): CustomVideoDecoderFactory, VideoDecoderFactory

### Community 54 - "Community 54"
Cohesion: 0.29
Nodes (3): FlutterAppDelegate, AppDelegate, -applicationdidFinishLaunchingWithOptions

### Community 55 - "Community 55"
Cohesion: 0.29
Nodes (6): FlutterBroadcastScreenCapturer, -appGroupIdentifier, -filePathForApplicationGroupIdentifier, -startCapture, -stopCapture, -stopCaptureWithCompletionHandler

### Community 56 - "Community 56"
Cohesion: 0.29
Nodes (6): FlutterScreenCaptureKitCapturer, -initWithDelegate, -selectDisplayFromContentsourceId, -startCaptureWithFPSsourceIdonStarted, -stopCaptureWithCompletion, -streamdidOutputSampleBufferofType

### Community 57 - "Community 57"
Cohesion: 0.43
Nodes (5): HandleMessage(), ProcessTasks(), RegisterWindowClass(), TaskRunnerWindows(), WndProc()

### Community 58 - "Community 58"
Cohesion: 0.67
Nodes (5): _dealInitialCards(), generateMinigameParams(), judgeMinigame(), pickMinigame(), sr()

### Community 59 - "Community 59"
Cohesion: 0.33
Nodes (5): canChallenge, FantasyWarsProximityService, forTarget, FwDuelProximityContext, ../../features/map/presentation/map_session_models.dart

### Community 60 - "Community 60"
Cohesion: 0.33
Nodes (1): PlaybackSamplesReadyCallbackAdapter

### Community 61 - "Community 61"
Cohesion: 0.33
Nodes (5): addTask, FlexQueue, FlexTask, FlexTaskAdd, FlexTaskRemove

### Community 62 - "Community 62"
Cohesion: 0.5
Nodes (1): Camera1Helper

### Community 63 - "Community 63"
Cohesion: 0.4
Nodes (3): FlutterRTCAudioSink, -close, -initWithAudioTrack

### Community 64 - "Community 64"
Cohesion: 0.4
Nodes (2): RunnerTests, XCTestCase

### Community 65 - "Community 65"
Cohesion: 0.4
Nodes (4): FLutterRTCVideoPlatformViewFactory, -createArgsCodec, -createWithFrameviewIdentifierarguments, -initWithMessenger

### Community 66 - "Community 66"
Cohesion: 0.4
Nodes (5): Principle 4: Manage Contracts With Code (Socket.IO event names centralized), socketProtocol.js Event Contract, socketRuntime.js Common Helpers, websocket/handlers/* Domain Handlers, websocket/index.js Registration Hub

### Community 67 - "Community 67"
Cohesion: 0.4
Nodes (5): Domain Layer (game rules), Infrastructure Layer, Presentation Layer, Provider/Application Layer, Principle 1: One File One Reason to Change

### Community 70 - "Community 70"
Cohesion: 0.5
Nodes (3): GameCatalog, GameDescriptor, hasCapability

### Community 71 - "Community 71"
Cohesion: 0.5
Nodes (1): EncoderConfig

### Community 72 - "Community 72"
Cohesion: 0.5
Nodes (1): AudioSinkBridge

### Community 73 - "Community 73"
Cohesion: 0.5
Nodes (1): FlutterWebRTCPluginImpl

### Community 76 - "Community 76"
Cohesion: 0.67
Nodes (1): GeneratedPluginRegistrant

### Community 77 - "Community 77"
Cohesion: 0.67
Nodes (1): AudioProcessingController

### Community 78 - "Community 78"
Cohesion: 0.67
Nodes (1): Callback

### Community 79 - "Community 79"
Cohesion: 0.67
Nodes (1): Point

### Community 80 - "Community 80"
Cohesion: 0.67
Nodes (1): webrtc()

### Community 81 - "Community 81"
Cohesion: 1.0
Nodes (2): MainActivity, FlutterActivity

### Community 82 - "Community 82"
Cohesion: 0.67
Nodes (2): UnimplementedError, WebRTC

### Community 83 - "Community 83"
Cohesion: 0.67
Nodes (1): flutter_webrtc_plugin()

### Community 84 - "Community 84"
Cohesion: 0.67
Nodes (2): Logger, LoggerDebug

### Community 86 - "Community 86"
Cohesion: 1.0
Nodes (1): MainActivity

### Community 97 - "Community 97"
Cohesion: 1.0
Nodes (1): registerPlugins

### Community 119 - "Community 119"
Cohesion: 1.0
Nodes (1): fromString

### Community 120 - "Community 120"
Cohesion: 1.0
Nodes (2): Principle 2: Prefer Domain Naming over generic get/query/build, Rationale: Generic names (get/query/build) created hub-like noise in graphify analysis

### Community 121 - "Community 121"
Cohesion: 1.0
Nodes (2): GameModePlugin (UI Layer), Rationale: GameModePlugin Stays Pure UI; Rules Live in Backend Plugin

### Community 227 - "Community 227"
Cohesion: 1.0
Nodes (1): Principle 3: Side Effects at Boundaries Only

### Community 228 - "Community 228"
Cohesion: 1.0
Nodes (1): Principle 5: Big Refactor Starts From Behavior Preservation

## Knowledge Gaps
- **1721 isolated node(s):** `EventBus`, `MainActivity`, `LocationApp`, `build`, `DefaultFirebaseOptions` (+1716 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 37`** (11 nodes): `AudioProcessingAdapter`, `.addProcessor()`, `.AudioProcessingAdapter()`, `.initialize()`, `.process()`, `.removeProcessor()`, `ExternalAudioFrameProcessing`, `.initialize()`, `.process()`, `.reset()`, `AudioProcessingAdapter.java`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 43`** (9 nodes): `SdkCapabilityChecker`, `.supportsDistortionCorrection()`, `.supportsEglRecordableAndroid()`, `.supportsEncoderProfiles()`, `.supportsMarshmallowNoiseReductionModes()`, `.supportsSessionConfiguration()`, `.supportsVideoPause()`, `.supportsZoomRatio()`, `SdkCapabilityChecker.java`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 53`** (7 nodes): `CustomVideoDecoderFactory.java`, `CustomVideoDecoderFactory`, `.CustomVideoDecoderFactory()`, `.getSupportedCodecs()`, `.setForceSWCodec()`, `.setForceSWCodecList()`, `VideoDecoderFactory`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 60`** (6 nodes): `PlaybackSamplesReadyCallbackAdapter`, `.addCallback()`, `.onWebRtcAudioTrackSamplesReady()`, `.PlaybackSamplesReadyCallbackAdapter()`, `.removeCallback()`, `PlaybackSamplesReadyCallbackAdapter.java`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 62`** (5 nodes): `Camera1Helper.java`, `Camera1Helper`, `.findClosestCaptureFormat()`, `.getCameraId()`, `.getSupportedFormats()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 64`** (5 nodes): `RunnerTests.m`, `RunnerTests.swift`, `RunnerTests`, `.testExample()`, `XCTestCase`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 71`** (4 nodes): `EncoderConfig.java`, `EncoderConfig`, `.EncoderConfig()`, `.toString()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 72`** (4 nodes): `AudioSinkBridge`, `.AudioSinkBridge()`, `audio_sink_bridge.cpp`, `audio_sink_bridge.cpp`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 73`** (4 nodes): `FlutterWebRTCPluginImpl`, `.FlutterWebRTCPluginImpl()`, `FlutterWebRTCPluginRegisterWithRegistrar()`, `flutter_webrtc_plugin.cc`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 76`** (3 nodes): `GeneratedPluginRegistrant.java`, `GeneratedPluginRegistrant`, `.registerWith()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 77`** (3 nodes): `AudioProcessingController`, `.AudioProcessingController()`, `AudioProcessingController.java`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 78`** (3 nodes): `Callback.java`, `Callback`, `.invoke()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 79`** (3 nodes): `Point`, `.Point()`, `Point.java`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 80`** (3 nodes): `webrtc()`, `media_stream_interface.h`, `media_stream_interface.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 81`** (3 nodes): `MainActivity.java`, `MainActivity`, `FlutterActivity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 82`** (3 nodes): `UnimplementedError`, `WebRTC`, `utils.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 83`** (3 nodes): `flutter_web_r_t_c_plugin.h`, `flutter_web_r_t_c_plugin.h`, `flutter_webrtc_plugin()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 84`** (3 nodes): `Logger`, `LoggerDebug`, `logger.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 86`** (2 nodes): `MainActivity.kt`, `MainActivity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 97`** (2 nodes): `registerPlugins`, `generated_plugin_registrant.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 119`** (2 nodes): `fromString`, `index.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 120`** (2 nodes): `Principle 2: Prefer Domain Naming over generic get/query/build`, `Rationale: Generic names (get/query/build) created hub-like noise in graphify analysis`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 121`** (2 nodes): `GameModePlugin (UI Layer)`, `Rationale: GameModePlugin Stays Pure UI; Rules Live in Backend Plugin`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 227`** (1 nodes): `Principle 3: Side Effects at Boundaries Only`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 228`** (1 nodes): `Principle 5: Big Refactor Starts From Behavior Preservation`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `get` connect `Android Audio Devices` to `E2EE Web Worker (compiled)`, `Community 33`, `WebRTC Codec Examples`, `Audio Processing & Auth`, `Backend AI & Game Loop`, `Android Audio Track`, `Android Audio Switch Manager`, `Backend Config & Services`, `Duel System Backend`, `AI Director (RAG)`, `Desktop Plugin Registrant`, `Flutter Desktop Codecs`?**
  _High betweenness centrality (0.260) - this node is a cross-community bridge._
- **Why does `package:flutter/material.dart` connect `Flutter App Shell` to `Audio Switch & CC Map Projection`, `WebRTC Codec Examples`, `BLE Presence Service`, `Android Audio Track`, `WebRTC Example UI`, `Duel System Backend`, `Color Chaser Flutter`, `Fantasy Wars Duel UI`, `WebRTC Tests`, `Fantasy Wars HUD`?**
  _High betweenness centrality (0.191) - this node is a cross-community bridge._
- **Why does `dart:async` connect `Audio Switch & CC Map Projection` to `Flutter App Shell`, `WebRTC Codec Examples`, `BLE Presence Service`, `Android Audio Track`, `WebRTC Example UI`, `Color Chaser Flutter`, `Fantasy Wars Duel UI`, `WebRTC Tests`?**
  _High betweenness centrality (0.093) - this node is a cross-community bridge._
- **Are the 221 inferred relationships involving `get` (e.g. with `createFastifyApp()` and `ask()`) actually correct?**
  _`get` has 221 INFERRED edges - model-reasoned connections that need verification._
- **Are the 81 inferred relationships involving `HandleMethodCall()` (e.g. with `.onMethodCall()` and `findMap()`) actually correct?**
  _`HandleMethodCall()` has 81 INFERRED edges - model-reasoned connections that need verification._
- **What connects `EventBus`, `MainActivity`, `LocationApp` to the rest of the system?**
  _1721 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Flutter App Shell` be split into smaller, more focused modules?**
  _Cohesion score 0.0 - nodes in this community are weakly interconnected._