import GamePluginRegistry from './GamePluginRegistry.js';
import AmongUsPlugin      from './AmongUsPlugin.js';

// 플러그인 등록 — 나중에 게임 추가 시 여기에 한 줄만 추가하면 됨
GamePluginRegistry.register(AmongUsPlugin);

export { GamePluginRegistry };
