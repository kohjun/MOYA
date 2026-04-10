// src/ai/AIDirector.js

import { GoogleGenerativeAI }    from '@google/generative-ai';
import { chat }                  from './LLMClient.js';
import { SYSTEM_PROMPT, PROMPTS } from './prompt.js';
import { retrieve }              from './rag/ragRetriever.js';
import { GamePluginRegistry }    from '../game/index.js';

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

const cooldowns = new Map();

function isOnCooldown(key, ms = 5000) {
  const last = cooldowns.get(key) || 0;
  if (Date.now() - last < ms) return true;
  cooldowns.set(key, Date.now());
  return false;
}

// ── 대화 히스토리 ────────────────────────────────────
const conversationHistory = new Map();
const MAX_TURNS = 10;

function getHistory(roomId, userId) {
  const key = `${roomId}_${userId}`;
  if (!conversationHistory.has(key)) conversationHistory.set(key, []);
  return conversationHistory.get(key);
}

function addHistory(roomId, userId, role, content) {
  const h = getHistory(roomId, userId);
  h.push({ role, content });
  if (h.length > MAX_TURNS * 2) h.splice(0, 2);
}

function clearHistory(roomId, userId) {
  conversationHistory.delete(`${roomId}_${userId}`);
}

// 게임 종료 시 해당 방의 히스토리 전체 정리
function cleanupRoom(roomId) {
  for (const key of conversationHistory.keys()) {
    if (key.startsWith(`${roomId}_`)) conversationHistory.delete(key);
  }
}

// ════════════════════════════════════════════════════
//  RAG 기반 질의응답
// ════════════════════════════════════════════════════

async function ask(room, player, question) {
  try {
    const plugin = GamePluginRegistry.get(room.gameType || 'among_us');
    const phase  = plugin.getCurrentPhase(room);

    const { context, sources, found } = await retrieve(
      question,
      room.gameType,
      player.team === 'impostor' ? 'impostor' : 'crew',
      phase
    );

    const systemPrompt = [
      plugin.getSystemPrompt(player.roleId, player.nickname),
      found ? `\n[관련 게임 규칙]\n${context}` : '',
      `\n[현재 게임 상황]\n${plugin.buildStateContext(room, player)}`,
    ].join('\n');

    const genModel = genAI.getGenerativeModel({
      model:             'gemini-2.5-flash',
      systemInstruction: systemPrompt,
    });

    const geminiHistory = getHistory(room.roomId, player.userId).map(msg => ({
      role:  msg.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: msg.content }],
    }));

    const chatSession = genModel.startChat({
      history:          geminiHistory,
      generationConfig: { maxOutputTokens: 500, temperature: 0.7 },
    });

    const res    = await chatSession.sendMessage(question);
    const answer = res.response.text().trim();

    addHistory(room.roomId, player.userId, 'user',      question);
    addHistory(room.roomId, player.userId, 'assistant', answer);

    return { answer, sources };

  } catch (e) {
    console.error('[AIDirector.ask] 오류:', e.message);
    return { answer: '죄송해요, 잠시 후 다시 물어봐주세요! 🙏', sources: [] };
  }
}

// ── 공개 해설 ─────────────────────────────────────────

async function onGameStart(room) {
  return chat({ prompt: PROMPTS.gameStart(room.players.size), systemPrompt: SYSTEM_PROMPT, model: 'fast' });
}

async function onKill(room, killer, target) {
  if (isOnCooldown(`${room.roomId}_kill`, 3000)) return null;
  return chat({
    prompt:       PROMPTS.kill(target.nickname, target.zone, room.killLog.length, room.aliveCrew?.length ?? 0),
    systemPrompt: SYSTEM_PROMPT,
    model:        'fast',
  });
}

async function onMeeting(room, caller, reason, body = null) {
  const prompt = reason === 'report' && body
    ? PROMPTS.bodyReport(caller.nickname, body.nickname, body.zone, room.meetingCount)
    : PROMPTS.emergencyMeeting(caller.nickname, room.meetingCount);
  return chat({ prompt, systemPrompt: SYSTEM_PROMPT, model: 'fast' });
}

async function onVoteResult(room, result, ejected) {
  let prompt;
  if (!ejected)                prompt = PROMPTS.ejectNone(result.isTied);
  else if (result.wasImpostor) prompt = PROMPTS.ejectImpostor(ejected.nickname, result.voteCount, room.aliveImpostors?.length ?? 0);
  else                         prompt = PROMPTS.ejectCrew(ejected.nickname, result.voteCount);
  return chat({ prompt, systemPrompt: SYSTEM_PROMPT, model: 'fast' });
}

async function onGameEnd(room, result) {
  const allImpostors = [...room.players.values()].filter(p => p.team === 'impostor').map(p => p.nickname);
  const prompt = result.winner === 'crew'
    ? PROMPTS.crewWin(result.reason, allImpostors)
    : PROMPTS.impostorWin(allImpostors);
  return chat({ prompt, systemPrompt: SYSTEM_PROMPT, model: 'fast' });
}

export {
  ask,
  onGameStart,
  onKill,
  onMeeting,
  onVoteResult,
  onGameEnd,
  cleanupRoom,
};
