// Fake Socket for handler tests.
// Records socket.emit calls into emits[].
// Stores on/once handlers so tests can trigger them via socket.trigger(event, ...args).

export function makeFakeSocket({ userId = 'u1', sessionId = 's1' } = {}) {
  const emits = [];
  const onHandlers = new Map();
  const onceHandlers = new Map();

  return {
    user: { id: userId, nickname: userId },
    currentSessionId: sessionId,
    emits,
    emit(event, payload) {
      emits.push({ event, payload });
    },
    on(event, handler) {
      onHandlers.set(event, handler);
    },
    once(event, handler) {
      onceHandlers.set(event, handler);
    },
    join() {},
    leave() {},
    trigger(event, ...args) {
      onHandlers.get(event)?.(...args);
      const once = onceHandlers.get(event);
      if (once) {
        onceHandlers.delete(event);
        once(...args);
      }
    },
    emitsFor(eventName) {
      return emits.filter((e) => e.event === eventName);
    },
    clearEmits() {
      emits.length = 0;
    },
  };
}
