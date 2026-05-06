// deferred(): manual-resolve Promise pair (race-condition test pattern).
// flushMicrotasks(rounds): yield to setImmediate `rounds` times so chained awaits + runExclusive
// mutex chains complete before assertions.

export function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

export async function flushMicrotasks(rounds = 4) {
  for (let i = 0; i < rounds; i += 1) {
    await new Promise((resolve) => setImmediate(resolve));
  }
}
