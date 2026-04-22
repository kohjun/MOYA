import GamePluginRegistry  from './GamePluginRegistry.js';
import AmongUsLegacyPlugin from './AmongUsLegacyPlugin.js';
import FantasyWarsPlugin   from './FantasyWarsPlugin.js';

// 플러그인 등록 — 새 게임 추가 시 여기에 한 줄만 추가
GamePluginRegistry.register(AmongUsLegacyPlugin);   // gameType: 'among_us'
GamePluginRegistry.register(FantasyWarsPlugin);      // gameType: 'fantasy_wars' (stub)

export { GamePluginRegistry };
