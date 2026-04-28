export const EVENTS = {
  // Client -> Server
  JOIN_SESSION: 'session:join',
  LEAVE_SESSION: 'session:leave',
  LOCATION_UPDATE: 'location:update',
  STATUS_UPDATE: 'status:update',
  SOS_TRIGGER: 'sos:trigger',
  ACTION_INTERACT: 'action:interact',
  GAME_START: 'game:start',
  GAME_REQUEST_STATE: 'game:request_state',
  GAME_AI_ASK: 'game:ai_ask',
  MEDIA_GET_ROUTER_RTP_CAPABILITIES: 'getRouterRtpCapabilities',
  MEDIA_GET_PRODUCERS: 'getProducers',
  MEDIA_CREATE_WEBRTC_TRANSPORT: 'createWebRtcTransport',
  MEDIA_CONNECT_WEBRTC_TRANSPORT: 'connectWebRtcTransport',
  MEDIA_PRODUCE: 'produce',
  MEDIA_CONSUME: 'consume',

  // Server -> Client
  SESSION_JOINED: 'session:joined',
  MEMBER_JOINED: 'member:joined',
  MEMBER_LEFT: 'member:left',
  MEMBER_UPDATED: 'member:updated',
  LOCATION_CHANGED: 'location:changed',
  STATUS_CHANGED: 'status:changed',
  SOS_ALERT: 'sos:alert',
  SESSION_SNAPSHOT: 'session:snapshot',
  KICKED: 'kicked',
  ROLE_CHANGED: 'role_changed',
  ACTION_RESULT: 'action:result',
  MODULE_ERROR: 'module:error',
  PLAYER_ELIMINATED: 'player:eliminated',
  GAME_OVER: 'game:over',
  GAME_STATE_UPDATE: 'game:state_update',
  GAME_STARTED: 'game:started',
  GAME_ROLE_ASSIGNED: 'game:role_assigned',
  GAME_AI_MESSAGE: 'game:ai_message',
  GAME_AI_REPLY: 'game:ai_reply',
  MEDIA_NEW_PRODUCER: 'media:newProducer',
  MEDIA_PRODUCER_CLOSED: 'media:producerClosed',
  VOICE_SPEAKING: 'voice:speaking',
  ERROR: 'error',

  // Fantasy Wars — 거점/스킬/던전 — Client -> Server
  FW_CAPTURE_START:  'fw:capture_start',
  FW_CAPTURE_CANCEL: 'fw:capture_cancel',
  FW_USE_SKILL:      'fw:use_skill',
  FW_ATTACK:         'fw:attack',
  FW_REVIVE:         'fw:revive',
  FW_DUNGEON_ENTER:  'fw:dungeon_enter',

  // Fantasy Wars — 대결 — Client -> Server
  FW_DUEL_CHALLENGE: 'fw:duel:challenge',
  FW_DUEL_ACCEPT:    'fw:duel:accept',
  FW_DUEL_REJECT:    'fw:duel:reject',
  FW_DUEL_CANCEL:    'fw:duel:cancel',
  FW_DUEL_SUBMIT:    'fw:duel:submit',

  // Fantasy Wars — 거점/스킬/던전 — Server -> Client
  FW_CAPTURE_STARTED:  'fw:capture_started',
  FW_CAPTURE_PROGRESS: 'fw:capture_progress',
  FW_CAPTURE_COMPLETE: 'fw:capture_complete',
  FW_CAPTURE_CANCELLED:'fw:capture_cancelled',
  FW_PLAYER_SKILL:     'fw:player_skill',
  FW_SKILL_COOLDOWN:   'fw:skill_cooldown',
  FW_SKILL_USED:       'fw:skill_used',
  FW_PLAYER_ATTACKED:  'fw:player_attacked',
  FW_PLAYER_ELIMINATED:'fw:player_eliminated',
  FW_PLAYER_REVIVED:   'fw:player_revived',
  FW_REVIVE_FAILED:    'fw:revive_failed',
  FW_ARTIFACT_TAKEN:   'fw:artifact_taken',
  FW_ARTIFACT_DROPPED: 'fw:artifact_dropped',
  FW_DUNGEON_CLEARED:  'fw:dungeon_cleared',

  // Color Chaser — Client -> Server
  CC_TAG_TARGET: 'cc:tag_target',
  CC_MISSION_START: 'cc:mission_start',
  CC_MISSION_SUBMIT: 'cc:mission_submit',
  CC_SET_BODY_PROFILE: 'cc:set_body_profile',

  // Color Chaser — Server -> Client (broadcast)
  CC_PLAYER_TAGGED: 'cc:player_tagged', // 처치 알림 (정체 포함, 게임 종료 또는 프라이버시 정책에 따라)
  CC_CP_ACTIVATED: 'cc:cp_activated',   // 새 거점 활성화 (위치 broadcast)
  CC_CP_CLAIMED: 'cc:cp_claimed',       // 누군가 미션 성공 → 거점 소비
  CC_CP_EXPIRED: 'cc:cp_expired',       // 시간 내 아무도 못 잡음

  // Fantasy Wars — 대결 — Server -> Client
  FW_DUEL_CHALLENGED:  'fw:duel:challenged',
  FW_DUEL_ACCEPTED:    'fw:duel:accepted',
  FW_DUEL_REJECTED:    'fw:duel:rejected',
  FW_DUEL_CANCELLED:   'fw:duel:cancelled',
  FW_DUEL_STARTED:     'fw:duel:started',
  FW_DUEL_RESULT:      'fw:duel:result',
  FW_DUEL_INVALIDATED: 'fw:duel:invalidated',
  FW_DUEL_LOG:         'fw:duel_log',
};
