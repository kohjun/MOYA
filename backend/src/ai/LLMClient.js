// src/ai/LLMClient.js

import { GoogleGenerativeAI } from '@google/generative-ai';

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

const MODELS = {
  fast:    'gemini-2.0-flash-lite',
  precise: 'gemini-2.5-flash',
};

const MAX_RETRIES  = 3;
const RETRY_DELAYS = [1000, 2000, 4000]; // 지수 백오프 (ms)

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function is503(err) {
  return (
    err?.status === 503 ||
    err?.statusCode === 503 ||
    (typeof err?.message === 'string' && err.message.includes('503'))
  );
}

async function callModel(modelName, { prompt, systemPrompt, maxTokens }) {
  const genModel = genAI.getGenerativeModel({
    model:             modelName,
    systemInstruction: systemPrompt,
  });
  const result = await genModel.generateContent({
    contents:         [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: { maxOutputTokens: maxTokens, temperature: 0.8 },
  });
  return result.response.text().trim();
}

async function chat({ prompt, systemPrompt, model = 'fast', maxTokens = 500 }) {
  const modelName = MODELS[model];

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    if (attempt > 0) {
      const delay = RETRY_DELAYS[attempt - 1];
      console.warn(`[LLM] 503 재시도 (${attempt}/${MAX_RETRIES}) — ${delay}ms 대기...`);
      await sleep(delay);
    }

    try {
      return await callModel(modelName, { prompt, systemPrompt, maxTokens });
    } catch (err) {
      const shouldRetry = is503(err) && attempt < MAX_RETRIES;
      if (shouldRetry) continue;

      // 재시도 소진 또는 503 아닌 오류
      if (model === 'precise') {
        // precise 최종 실패 → gemini-2.0-flash-lite 폴백
        console.warn(`[LLM] ${modelName} 실패 (${err.message}), gemini-2.0-flash-lite 폴백`);
        try {
          return await callModel(MODELS.fast, { prompt, systemPrompt, maxTokens });
        } catch (fallbackErr) {
          console.error('[LLM] 폴백도 실패:', fallbackErr.message);
          return getFallbackMessage(prompt);
        }
      }

      // fast 실패 → 정적 메시지 반환
      console.error('[LLM] API 오류:', err.message);
      return getFallbackMessage(prompt);
    }
  }

  return getFallbackMessage(prompt);
}

// API 장애 시 fallback
function getFallbackMessage(prompt) {
  if (prompt.includes('킬'))   return '🔴 이상한 낌새가 느껴집니다...';
  if (prompt.includes('회의')) return '🚨 긴급 회의가 소집됩니다!';
  if (prompt.includes('추방')) return '⚖️ 투표 결과가 나왔습니다.';
  if (prompt.includes('미션')) return '📋 미션을 계속 진행하세요.';
  return '👁️ 모든 것을 지켜보고 있습니다...';
}

export { chat };
