// 판타지 워즈 알림 카탈로그.
//
// 게임 중 발생하는 13가지 핵심 이벤트 → 사용자가 인지해야 할 알림 (텍스트 +
// 사운드 + 햅틱 + 토스트 컬러) 매핑. fw_notification_service 가 이 카탈로그를
// 보고 dedupe / priority / 재생을 처리한다.
//
// 사운드 자산은 assets/sounds/fw/<kind>.mp3 경로를 가정. 자산이 없으면
// AudioPlayer 가 silent 폴백 (catch + 무시) — 텍스트/햅틱은 정상 작동.

enum FwNotifyKind {
  cpCapturedByUs,
  cpCapturedByEnemy,
  cpBeingCapturedByEnemy,
  cpBlockadedAgainstUs,
  duelChallengedToMe,
  duelWon,
  duelLost,
  shieldConsumed,
  eliminatedSelf,
  revived,
  masterEliminatedUs,
  gameWon,
  gameLost,
}

enum FwNotifyHaptic { none, light, medium, heavy }

class FwNotifyPreset {
  const FwNotifyPreset({
    required this.text,
    required this.soundAsset,
    required this.haptic,
    required this.toastKind,
    this.dedupeMs = 3000,
  });

  // params 에서 동적으로 텍스트를 만든다 (cp 이름, 길드명 등).
  final String Function(Map<String, dynamic> params) text;
  // assets/sounds/fw/<file>.mp3 형태의 상대 경로. null = 무음.
  final String? soundAsset;
  final FwNotifyHaptic haptic;
  // FwToastOverlay 가 이미 인식하는 kind 값 (capture/combat/duel/skill/revive/match).
  final String toastKind;
  // 같은 kind 가 N ms 안에 또 fire 되면 무시 (점령 진행 중 매초 fire 방지).
  final int dedupeMs;
}

String _pCp(Map<String, dynamic> p) =>
    (p['cpName'] as String?) ?? '거점';
String _pGuild(Map<String, dynamic> p) =>
    (p['guildName'] as String?) ?? '적 길드';
String _pOpp(Map<String, dynamic> p) =>
    (p['opponentName'] as String?) ?? '상대';

const Map<FwNotifyKind, FwNotifyPreset> kFwNotifyCatalog = {
  FwNotifyKind.cpCapturedByUs: FwNotifyPreset(
    text: _textCpCapturedByUs,
    soundAsset: 'sounds/fw/cp_captured_us.mp3',
    haptic: FwNotifyHaptic.medium,
    toastKind: 'capture',
  ),
  FwNotifyKind.cpCapturedByEnemy: FwNotifyPreset(
    text: _textCpCapturedByEnemy,
    soundAsset: 'sounds/fw/cp_captured_enemy.mp3',
    haptic: FwNotifyHaptic.medium,
    toastKind: 'capture',
  ),
  FwNotifyKind.cpBeingCapturedByEnemy: FwNotifyPreset(
    text: _textCpBeingCapturedByEnemy,
    soundAsset: 'sounds/fw/cp_warning.mp3',
    haptic: FwNotifyHaptic.light,
    toastKind: 'capture',
    dedupeMs: 8000, // 한 점령 시도 동안 1번만 알리도록 dedupe 더 길게
  ),
  FwNotifyKind.cpBlockadedAgainstUs: FwNotifyPreset(
    text: _textCpBlockadedAgainstUs,
    soundAsset: 'sounds/fw/blockade_seal.mp3',
    haptic: FwNotifyHaptic.light,
    toastKind: 'skill',
  ),
  FwNotifyKind.duelChallengedToMe: FwNotifyPreset(
    text: _textDuelChallenged,
    soundAsset: 'sounds/fw/duel_challenge.mp3',
    haptic: FwNotifyHaptic.medium,
    toastKind: 'duel',
  ),
  FwNotifyKind.duelWon: FwNotifyPreset(
    text: _textDuelWon,
    soundAsset: 'sounds/fw/duel_won.mp3',
    haptic: FwNotifyHaptic.light,
    toastKind: 'duel',
  ),
  FwNotifyKind.duelLost: FwNotifyPreset(
    text: _textDuelLost,
    soundAsset: 'sounds/fw/duel_lost.mp3',
    haptic: FwNotifyHaptic.medium,
    toastKind: 'duel',
  ),
  FwNotifyKind.shieldConsumed: FwNotifyPreset(
    text: _textShieldConsumed,
    soundAsset: 'sounds/fw/shield_block.mp3',
    haptic: FwNotifyHaptic.medium,
    toastKind: 'skill',
  ),
  FwNotifyKind.eliminatedSelf: FwNotifyPreset(
    text: _textEliminatedSelf,
    soundAsset: 'sounds/fw/eliminated.mp3',
    haptic: FwNotifyHaptic.heavy,
    toastKind: 'combat',
  ),
  FwNotifyKind.revived: FwNotifyPreset(
    text: _textRevived,
    soundAsset: 'sounds/fw/revive.mp3',
    haptic: FwNotifyHaptic.medium,
    toastKind: 'revive',
  ),
  FwNotifyKind.masterEliminatedUs: FwNotifyPreset(
    text: _textMasterEliminatedUs,
    soundAsset: 'sounds/fw/master_down.mp3',
    haptic: FwNotifyHaptic.heavy,
    toastKind: 'combat',
  ),
  FwNotifyKind.gameWon: FwNotifyPreset(
    text: _textGameWon,
    soundAsset: 'sounds/fw/victory.mp3',
    haptic: FwNotifyHaptic.heavy,
    toastKind: 'match',
  ),
  FwNotifyKind.gameLost: FwNotifyPreset(
    text: _textGameLost,
    soundAsset: 'sounds/fw/defeat.mp3',
    haptic: FwNotifyHaptic.heavy,
    toastKind: 'match',
  ),
};

String _textCpCapturedByUs(Map<String, dynamic> p) =>
    '${_pCp(p)} 확보!';
String _textCpCapturedByEnemy(Map<String, dynamic> p) =>
    '${_pCp(p)}이(가) ${_pGuild(p)}에게 넘어갔다';
String _textCpBeingCapturedByEnemy(Map<String, dynamic> p) =>
    '${_pGuild(p)}가 ${_pCp(p)} 점령 중!';
String _textCpBlockadedAgainstUs(Map<String, dynamic> p) =>
    '${_pCp(p)} 봉쇄됨';
String _textDuelChallenged(Map<String, dynamic> p) =>
    '${_pOpp(p)}이(가) 결투 신청';
String _textDuelWon(Map<String, dynamic> p) => '결투 승리';
String _textDuelLost(Map<String, dynamic> p) => '결투 패배';
String _textShieldConsumed(Map<String, dynamic> p) =>
    '보호막이 결투를 막아냈다';
String _textEliminatedSelf(Map<String, dynamic> p) =>
    '탈락 — 던전으로 이동';
String _textRevived(Map<String, dynamic> p) => '부활 성공';
String _textMasterEliminatedUs(Map<String, dynamic> p) =>
    '마스터 탈락 — 길드 위기';
String _textGameWon(Map<String, dynamic> p) => '승리!';
String _textGameLost(Map<String, dynamic> p) => '패배';
