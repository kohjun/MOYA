import { GoogleGenerativeAI } from '@google/generative-ai';

import { chat } from './LLMClient.js';
import { FW_SYSTEM_PROMPT, FW_PROMPTS } from './prompt.js';
import { retrieve } from './rag/ragRetriever.js';
import { GamePluginRegistry } from '../game/index.js';
import { redisClient } from '../config/redis.js';

const PRIMARY_MODEL = 'gemini-2.5-flash';
const RETRY_DELAYS_MS = [1000, 2000, 4000];

const MAX_TURNS = 10;
const HISTORY_TTL_SECONDS = 60 * 60 * 24;
// Redis 키 프리픽스
const COOLDOWN_PREFIX = 'ai:cooldown:';
const HISTORY_PREFIX  = 'ai:history:';

/**
 * Redis SET + EX 기반 쿨다운 체크.
 * 키가 이미 존재하면 쿨다운 중(true), 없으면 키를 심고 false 반환.
 */
async function isOnCooldown(key, ms = 5000) {
  const redisKey = `${COOLDOWN_PREFIX}${key}`;
  const ttlSeconds = Math.ceil(ms / 1000);
  // SET NX EX: 키가 없을 때만 삽입. 삽입 성공 → 쿨다운 아님, null 반환 → 쿨다운 중
  const result = await redisClient.set(redisKey, '1', { NX: true, EX: ttlSeconds });
  return result === null; // null이면 이미 존재(쿨다운 중)
}

/**
 * Redis List(LPUSH)에서 대화 기록 읽기.
 * LPUSH는 최신을 앞에 저장하므로 LRANGE 후 reverse해 시간순으로 반환.
 */
async function getHistory(roomId, userId) {
  const key = `${HISTORY_PREFIX}${roomId}:${userId}`;
  const items = await redisClient.lRange(key, 0, -1);
  return items.reverse().map((item) => JSON.parse(item));
}

/**
 * Redis List(LPUSH)에 메시지 추가 후 LTRIM으로 MAX_TURNS 유지.
 * LPUSH 특성상 최신 항목이 인덱스 0에 위치하며, LTRIM 0 ~(MAX_TURNS*2-1)로 잘라낸다.
 */
async function addHistory(roomId, userId, role, content) {
  const key = `${HISTORY_PREFIX}${roomId}:${userId}`;
  await redisClient.lPush(key, JSON.stringify({ role, content }));
  await redisClient.lTrim(key, 0, MAX_TURNS * 2 - 1);
  await redisClient.expire(key, HISTORY_TTL_SECONDS);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isGeminiCredentialError(error) {
  const message = `${error?.message ?? ''}`;
  return (
    message.includes('API key was reported as leaked') ||
    message.includes('403 Forbidden') ||
    message.includes('API_KEY_INVALID') ||
    message.includes('PERMISSION_DENIED')
  );
}

function isGeminiOverloadError(error) {
  const message = `${error?.message ?? ''}`;
  return (
    error?.status === 503 ||
    error?.statusCode === 503 ||
    message.includes('503 Service Unavailable') ||
    message.includes('currently experiencing high demand') ||
    message.includes('UNAVAILABLE')
  );
}

function createGenerativeModel(model, systemPrompt) {
  return new GoogleGenerativeAI(process.env.GEMINI_API_KEY).getGenerativeModel({
    model,
    systemInstruction: systemPrompt,
  });
}

async function askWithModel({ model, systemPrompt, history, question }) {
  const chatSession = createGenerativeModel(model, systemPrompt).startChat({
    history,
    generationConfig: {
      maxOutputTokens: 1500,
      temperature: 0.7,
    },
  });

  const result = await chatSession.sendMessage(question);
  return result.response.text().trim();
}

async function askWithRetry({ systemPrompt, history, question }) {
  let lastError = null;
  const attempts = RETRY_DELAYS_MS.length + 1;

  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    if (attempt > 1) {
      const delay =
        RETRY_DELAYS_MS[Math.min(attempt - 2, RETRY_DELAYS_MS.length - 1)];
      console.warn(
        `[AIDirector.ask] ${PRIMARY_MODEL} retry ${attempt - 1}/${attempts - 1} after ${delay}ms`,
      );
      await sleep(delay);
    }

    try {
      return await askWithModel({
        model: PRIMARY_MODEL,
        systemPrompt,
        history,
        question,
      });
    } catch (error) {
      lastError = error;

      if (isGeminiCredentialError(error)) {
        throw error;
      }

      const canRetryCurrentModel =
        isGeminiOverloadError(error) && attempt < attempts;
      if (canRetryCurrentModel) {
        continue;
      }

      break;
    }
  }

  throw lastError ?? new Error('Gemini request failed');
}

function buildAskFailure(error) {
  if (!process.env.GEMINI_API_KEY || isGeminiCredentialError(error)) {
    return {
      answer:
        'AI MOYA가 지금은 오프라인 상태입니다. Gemini API 키가 차단되었거나 교체가 필요합니다. 운영 키가 갱신되면 다시 질문할 수 있습니다.',
      sources: [],
      isError: true,
      errorCode: 'AI_KEY_INVALID',
    };
  }

  if (isGeminiOverloadError(error)) {
    return {
      answer:
        'AI MOYA 요청이 잠시 몰려서 답변이 지연되고 있습니다. 잠시 후 다시 질문해 주세요.',
      sources: [],
      isError: true,
      errorCode: 'AI_TEMPORARILY_BUSY',
    };
  }

  return {
    answer: 'AI MOYA가 잠시 응답하지 못했습니다. 잠시 후 다시 질문해 주세요.',
    sources: [],
    isError: true,
    errorCode: 'AI_UNAVAILABLE',
  };
}

async function ask(room, player, question) {
  try {
    if (!process.env.GEMINI_API_KEY) {
      return buildAskFailure(new Error('Missing GEMINI_API_KEY'));
    }

    const plugin = GamePluginRegistry.get(room.gameType || 'fantasy_wars_artifact');
    const phase = plugin.getCurrentPhase(room);
    // 플러그인이 자기 지식베이스에 맞는 role 태그를 결정한다 (없으면 player.roleId/team 폴백).
    const knowledgeRole = plugin.getKnowledgeRole?.(player, room)
      ?? player.roleId
      ?? player.team
      ?? 'all';

    const { context, sources, found } = await retrieve(
      question,
      room.gameType,
      knowledgeRole,
      phase,
    );

    const systemPrompt = [
      plugin.getSystemPrompt(player.roleId, player.nickname),
      found ? `\n[관련 게임 규칙]\n${context}` : '',
      `\n[현재 게임 상황]\n${plugin.buildStateContext(room, player)}`,
      '\n[응답 규칙] 답변은 반드시 완성된 문장으로 마무리해. 중간에 끊기지 말고 자연스럽게 끝내.',
    ].join('\n');

    // Redis에서 전체 기록 로드 후 Gemini 포맷으로 변환
    const allHistory = (await getHistory(room.roomId, player.userId)).map((message) => ({
      role: message.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: message.content }],
    }));

    // 토큰 절감: Gemini에는 최신 4개 항목(≈2턴)만 주입
    const history = allHistory.slice(-4);

    const answer = await askWithRetry({
      systemPrompt,
      history,
      question,
    });

    await addHistory(room.roomId, player.userId, 'user', question);
    await addHistory(room.roomId, player.userId, 'assistant', answer);

    return { answer, sources, isError: false };
  } catch (error) {
    console.error('[AIDirector.ask] error:', error.message);
    return buildAskFailure(error);
  }
}

async function clearHistory(roomId, userId) {
  await redisClient.del(`${HISTORY_PREFIX}${roomId}:${userId}`);
}

async function cleanupRoom(roomId) {
  // KEYS는 소규모 데이터에 한해 허용; 대규모 환경에서는 SCAN으로 교체 권장
  const keys = await redisClient.keys(`${HISTORY_PREFIX}${roomId}:*`);
  if (keys.length > 0) {
    await redisClient.del(keys);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fantasy Wars 이벤트 핸들러
// ─────────────────────────────────────────────────────────────────────────────

async function fwOnGameStart(room) {
  const guildCount  = room.pluginState?.guilds ? Object.keys(room.pluginState.guilds).length : 3;
  const playerCount = room.alivePlayerIds?.length ?? 0;
  try {
    return await chat({
      prompt: FW_PROMPTS.gameStart(guildCount, playerCount),
      systemPrompt: FW_SYSTEM_PROMPT,
      model: 'fast',
      maxTokens: 1024,
    });
  } catch (error) {
    console.warn('[AIDirector] fwOnGameStart suppressed:', error?.message ?? error);
    return null;
  }
}

async function fwOnCpCaptured(room, guildId, cpName) {
  if (await isOnCooldown(`${room.roomId}_cp`, 4000)) return null;
  const cps        = room.pluginState?.controlPoints ?? [];
  const captured   = cps.filter(cp => cp.capturedBy === guildId).length;
  return chat({
    prompt: FW_PROMPTS.cpCaptured(guildId, cpName, captured, cps.length),
    systemPrompt: FW_SYSTEM_PROMPT,
    model: 'fast',
  });
}

async function fwOnDuelResult(room, winner, loser, minigameType, executionTriggered) {
  if (await isOnCooldown(`${room.roomId}_duel`, 3000)) return null;
  return chat({
    prompt: FW_PROMPTS.duelResult(
      winner?.nickname ?? winner?.userId ?? '?',
      loser?.nickname  ?? loser?.userId  ?? '?',
      minigameType,
      executionTriggered,
    ),
    systemPrompt: FW_SYSTEM_PROMPT,
    model: 'fast',
  });
}

async function fwOnDuelDraw(room, minigameType) {
  return chat({
    prompt: FW_PROMPTS.duelDraw(minigameType),
    systemPrompt: FW_SYSTEM_PROMPT,
    model: 'fast',
  });
}

async function fwOnPlayerEliminated(room, player) {
  if (await isOnCooldown(`${room.roomId}_elim`, 3000)) return null;
  return chat({
    prompt: FW_PROMPTS.playerEliminated(
      player?.nickname ?? player?.userId ?? '?',
      player?.guildId  ?? '?',
    ),
    systemPrompt: FW_SYSTEM_PROMPT,
    model: 'fast',
  });
}

async function fwOnGameEnd(room, winnerGuildId, reason) {
  return chat({
    prompt: FW_PROMPTS.gameEnd(winnerGuildId, reason),
    systemPrompt: FW_SYSTEM_PROMPT,
    model: 'fast',
  });
}

export {
  ask,
  clearHistory,
  cleanupRoom,
  fwOnGameStart,
  fwOnCpCaptured,
  fwOnDuelResult,
  fwOnDuelDraw,
  fwOnPlayerEliminated,
  fwOnGameEnd,
};
