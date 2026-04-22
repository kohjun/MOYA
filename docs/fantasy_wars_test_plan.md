# Fantasy Wars Test Plan

## Automated checks

### Backend

Run from `C:\MOYA\backend`:

```powershell
cmd /c npm test
```

Covered by unit tests:

- Fantasy Wars ruleset defaults
- Capture validation and intent readiness
- Capture state reset and cancellation
- Revive chance and revive success state restoration
- Skill validation and shield/blockade/reveal/execution effects
- Duel resolution rules
  - warrior two-life handling
  - shield absorption
  - rogue execution

### Flutter

Run from `C:\MOYA\flutter`:

```powershell
flutter test
```

Covered by tests:

- Fantasy Wars model parsing
- Provider hydration from `game:state_update`
- Provider HP sync for `fw:player_attacked`
- Provider duel lifecycle updates
- Basic smoke test

## Manual scenario checklist

### 1. Session start

- Create a `fantasy_wars_artifact` session with a valid playable area or explicit control points.
- Join with at least 6 test users across 3 guilds.
- Start the game and confirm:
  - each user gets one of `warrior/priest/mage/ranger/rogue`
  - exactly one guild master is assigned per guild
  - 5 control points appear on the map
  - no legacy `archer/healer/scout` labels appear in UI

### 2. Capture preparation

- Move only 1 same-guild player into a control point radius and press capture.
  - Expected: capture is rejected.
- Move 2 same-guild players into the radius but have only 1 press capture.
  - Expected: capture does not start.
- Have both same-guild players press capture within the ready window.
  - Expected: `fw:capture_progress` then `fw:capture_started` are emitted.

### 3. Capture interrupt

- Start a valid capture with 2 allies.
- Move 1 enemy into the same control point radius and trigger interrupt.
  - Expected: active capture is cancelled immediately.
  - Expected: control point returns to neutral or previous owner state.
- Remove the enemy and retry capture.
  - Expected: capture can start again normally.

### 4. Duel rules

- Warrior loses once.
  - Expected: remains alive with `remainingLives = 1`.
- Priest shield target loses a duel.
  - Expected: shield is consumed and target does not enter dungeon.
- Rogue arms execution and wins against an unshielded target.
  - Expected: target is eliminated immediately even if target is warrior.
- Rogue arms execution and wins against a shielded target.
  - Expected: shield breaks, target survives, execution buff is consumed.
- Disconnect one duel participant mid-match.
  - Expected: duel invalidates and both return to idle without penalty.

### 5. Dungeon revive

- Eliminate a player and enter dungeon.
  - Expected: revive chance starts at `30%`.
- Fail one revive attempt.
  - Expected: next chance increases to `40%`.
- Fail repeatedly.
  - Expected: chance increases by `10%` each time, capped at `100%`.
- Succeed on revive.
  - Expected: player returns alive, exits dungeon, revive attempts reset.
- Re-eliminate the same player and re-enter dungeon.
  - Expected: revive chance starts again from `30%`.

### 6. Skill restrictions

- Cast priest shield on a player currently in duel.
  - Expected: request is rejected.
- Cast mage blockade on a control point, then attempt capture there.
  - Expected: capture is rejected while blockade is active.
- Cast ranger reveal on an enemy.
  - Expected: tracked target appears in UI for 1 minute.

### 7. Win conditions

- Capture 3 of 5 control points with one guild.
  - Expected: game ends with control-point victory.
- Eliminate all opposing guild masters before majority capture.
  - Expected: game ends with guild-master-elimination victory.

## Regression focus after each gameplay bug fix

- Run backend tests.
- Run Flutter tests.
- Replay one duel scenario and one capture scenario manually.
- Verify `game:state_update` still includes dungeons, artifact, shields, reveal, and duel flags.
