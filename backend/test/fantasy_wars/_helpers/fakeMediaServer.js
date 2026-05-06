// Fake MediaServer for winFlow / game-over tests.
// makeFakeMediaServer() — drop-in for getMediaServer(): exposes getRoom(sessionId)
//   and records every call into mediaServer.calls.
// makeFakeSyncMediaRoomState() — drop-in for syncMediaRoomState: records (sessionId, room)
//   and resolves to null. Tests can inspect calls.

export function makeFakeMediaServer({ rooms = new Map() } = {}) {
  const calls = [];
  return {
    calls,
    getRoom(sessionId) {
      calls.push({ method: 'getRoom', sessionId });
      if (rooms.has(sessionId)) {
        return rooms.get(sessionId);
      }
      const room = { sessionId, _stub: true };
      rooms.set(sessionId, room);
      return room;
    },
    setRoom(sessionId, room) {
      rooms.set(sessionId, room);
    },
    deleteRoom(sessionId) {
      rooms.delete(sessionId);
    },
  };
}

export function makeFakeSyncMediaRoomState() {
  const calls = [];
  const fn = async (sessionId, room) => {
    calls.push({ sessionId, room });
    return null;
  };
  fn.calls = calls;
  return fn;
}
