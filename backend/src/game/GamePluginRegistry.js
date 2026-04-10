'use strict';

const plugins = new Map();

function register(plugin) {
  plugins.set(plugin.gameType, plugin);
}

function get(gameType) {
  const plugin = plugins.get(gameType);
  if (!plugin) throw new Error(`게임 플러그인 없음: ${gameType}`);
  return plugin;
}

function list() {
  return [...plugins.values()].map(p => ({
    gameType:    p.gameType,
    displayName: p.displayName,
    configSchema: p.configSchema,
  }));
}

export default { register, get, list };
