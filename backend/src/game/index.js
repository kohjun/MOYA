import GamePluginRegistry from './GamePluginRegistry.js';
import FantasyWarsPlugin from './FantasyWarsPlugin.js';
import ColorChaserPlugin from './plugins/color_chaser/index.js';

GamePluginRegistry.register(FantasyWarsPlugin);
GamePluginRegistry.register(ColorChaserPlugin);

export { GamePluginRegistry };
