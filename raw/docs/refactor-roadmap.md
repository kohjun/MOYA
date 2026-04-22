# Refactor Roadmap

## Goal

Stabilize backend and Flutter runtime contracts first, then split oversized UI/state modules with low regression risk.

## Scope

1. Backend contract and game state normalization
2. Flutter socket event subscription leak removal
3. `map_screen.dart` state, model, and UI separation
4. Minimal regression checks and static verification

## Progress

### 1. Backend contract and game state normalization

Status: completed

- Move `users.current_session_id` foreign key addition until after `sessions` table creation
- Persist and enforce `durationHours` and `maxMembers`
- Unify FCM token update routes through the service layer
- Normalize Redis game state to `status: in_progress` and `alivePlayerIds`
- Fix expired-session room broadcast target

### 2. Flutter socket event subscription leak removal

Status: completed

- Replace per-listener `socket.on(...)` registration with shared broadcast controllers
- Forward game events once during socket handler registration
- Close and clear dynamic game event controllers in `dispose()`

### 3. `map_screen.dart` split

Status: in_progress

Target split:

- Extract session/member/game view models into a dedicated file
- Move socket subscription wiring out of the widget-facing notifier where possible
- Separate map marker rendering helpers from session orchestration logic

Execution order:

1. Remove dead imports and unused helpers
2. Extract pure data models with no widget dependencies
3. Extract socket/listener glue into focused private helpers
4. Extract leaf widgets only after analyzer stays clean

Risk:

- The file currently has mixed encoding artifacts, so broad rewrites are unsafe
- Only small `apply_patch` edits should be used until the file is normalized

### 4. Regression checks

Status: completed

- Keep `flutter analyze` clean except for known pre-existing warnings
- Keep backend files passing `node --check`
- Add lightweight tests only where there is an existing runner or a pure logic seam

## Current verification baseline

- Backend syntax checks pass on the modified files
- `flutter analyze` currently reports no issues

## Next action

Start step 3 with warning cleanup and only then attempt small, isolated extractions from `map_screen.dart`.
