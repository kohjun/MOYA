// In-memory replacement for socketRuntime.readGameState/saveGameState.
// Deep-clones on read and write so handler in-place mutation does not bleed across calls.

function clone(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

export function makeFakeGameStateStore(initial = null) {
  let store = clone(initial);

  return {
    readState: async () => clone(store),
    saveState: async (gs) => {
      store = clone(gs);
      return store;
    },
    snapshot: () => clone(store),
    set: (gs) => {
      store = clone(gs);
    },
  };
}
