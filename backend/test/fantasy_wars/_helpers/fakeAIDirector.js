// Fake AIDirector for winFlow tests.
// makeFakeAIDirector(message): records every fwOnGameEnd call and returns
// the configured message (or null) so the .then(...) emit branch is deterministic.

export function makeFakeAIDirector(message) {
  const calls = [];
  return {
    calls,
    fwOnGameEnd: async (room, winner, reason) => {
      calls.push({ room, winner, reason });
      return message;
    },
  };
}
