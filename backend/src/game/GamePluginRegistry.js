'use strict';

const plugins = new Map();
const aliases = new Map([
  ['fantasy_wars', 'fantasy_wars_artifact'],
]);

function register(plugin) {
  plugins.set(plugin.gameType, plugin);
}

function get(gameType) {
  const resolvedGameType = aliases.get(gameType) ?? gameType;
  const plugin = plugins.get(resolvedGameType);
  if (!plugin) {
    throw new Error(`Game plugin not found: ${gameType}`);
  }
  return plugin;
}

function list() {
  return [...plugins.values()].map((plugin) => ({
    gameType: plugin.gameType,
    displayName: plugin.displayName,
    configSchema: plugin.configSchema,
    defaultConfig: plugin.defaultConfig ?? {},
    capabilities: plugin.capabilities ?? [],
  }));
}

export default { register, get, list };
