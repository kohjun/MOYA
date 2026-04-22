'use strict';

// ─────────────────────────────────────────────────────────────────────────────
// TransportAdapter — transport-agnostic messaging interface
//
// DuelService는 이 인터페이스를 통해 메시지를 보냄.
// BLE / Socket / UWB 구현체를 교체해도 DuelService 코드는 불변.
// ─────────────────────────────────────────────────────────────────────────────

export class TransportAdapter {
  // 특정 유저에게 이벤트 전송
  sendToUser(userId, event, payload) {
    throw new Error('TransportAdapter.sendToUser: NOT_IMPLEMENTED');
  }
  // 세션 전체에 이벤트 브로드캐스트
  sendToSession(sessionId, event, payload) {
    throw new Error('TransportAdapter.sendToSession: NOT_IMPLEMENTED');
  }
}

// ── Socket.IO 구현체 ──────────────────────────────────────────────────────────

export class SocketTransportAdapter extends TransportAdapter {
  constructor(io) {
    super();
    this._io = io;
  }

  sendToUser(userId, event, payload) {
    this._io.to(`user:${userId}`).emit(event, payload);
  }

  sendToSession(sessionId, event, payload) {
    this._io.to(`session:${sessionId}`).emit(event, payload);
  }
}

// ── BLE 구현체 (stub) ─────────────────────────────────────────────────────────
// BLE transport가 준비되면 bleServer.sendToDevice() 호출로 교체.

export class BleTransportAdapter extends TransportAdapter {
  constructor(bleServer) {
    super();
    this._ble = bleServer;
  }

  sendToUser(userId, event, payload) {
    // this._ble.sendToDevice(userId, JSON.stringify({ event, payload }));
    throw new Error('BleTransportAdapter: NOT_YET_IMPLEMENTED');
  }

  sendToSession(sessionId, event, payload) {
    // this._ble.broadcastToSession(sessionId, JSON.stringify({ event, payload }));
    throw new Error('BleTransportAdapter: NOT_YET_IMPLEMENTED');
  }
}
