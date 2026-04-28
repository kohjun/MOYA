'use strict';

// 같은 key에 대한 작업을 직렬화하는 인프로세스 mutex.
// 단일 노드 가정. 멀티노드 배포 시에는 redlock 등 분산 락으로 교체 필요.
const chains = new Map();

export function runExclusive(key, fn) {
  const prev = chains.get(key) ?? Promise.resolve();
  const result = prev.then(fn, fn);
  const tail = result.catch(() => {});
  chains.set(key, tail);
  tail.finally(() => {
    if (chains.get(key) === tail) {
      chains.delete(key);
    }
  });
  return result;
}
