// Fake socket.io Server for handler tests.
// Records every io.to(room).emit(event, payload) call into events[].

export function makeFakeIo() {
  const events = [];

  return {
    events,
    to(room) {
      return {
        emit(event, payload) {
          events.push({ room, event, payload });
        },
      };
    },
    eventsFor(eventName) {
      return events.filter((e) => e.event === eventName);
    },
    eventsToRoom(roomPrefix) {
      return events.filter((e) => e.room.startsWith(roomPrefix));
    },
    clear() {
      events.length = 0;
    },
  };
}
