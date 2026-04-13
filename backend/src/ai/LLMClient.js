// src/ai/LLMClient.js

import { GoogleGenerativeAI } from '@google/generative-ai';

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

const MODELS = {
  fast: 'gemini-2.5-flash',
  precise: 'gemini-2.5-flash',
};

const MAX_RETRIES = 3;
const RETRY_DELAYS = [1000, 2000, 4000];

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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
    model: modelName,
    systemInstruction: systemPrompt,
  });

  const result = await genModel.generateContent({
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: { maxOutputTokens: maxTokens, temperature: 0.8 },
  });

  return result.response.text().trim();
}

async function chat({ prompt, systemPrompt, model = 'fast', maxTokens = 500 }) {
  const modelName = MODELS[model] ?? MODELS.fast;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt += 1) {
    if (attempt > 0) {
      const delay = RETRY_DELAYS[attempt - 1];
      console.warn(`[LLM] 503 retry (${attempt}/${MAX_RETRIES}) after ${delay}ms`);
      await sleep(delay);
    }

    try {
      return await callModel(modelName, { prompt, systemPrompt, maxTokens });
    } catch (err) {
      const shouldRetry = is503(err) && attempt < MAX_RETRIES;
      if (shouldRetry) continue;

      if (model === 'precise') {
        console.warn(
          `[LLM] ${modelName} failed (${err.message}), retrying once with ${MODELS.fast}`,
        );
        try {
          return await callModel(MODELS.fast, {
            prompt,
            systemPrompt,
            maxTokens,
          });
        } catch (fallbackErr) {
          console.error('[LLM] fallback failed:', fallbackErr.message);
          return getFallbackMessage(prompt);
        }
      }

      console.error('[LLM] API error:', err.message);
      return getFallbackMessage(prompt);
    }
  }

  return getFallbackMessage(prompt);
}

function getFallbackMessage(prompt) {
  if (prompt.includes('kill')) return 'A new sign of danger is in the air...';
  if (prompt.includes('meeting')) return 'An emergency meeting has begun.';
  if (prompt.includes('vote')) return 'The vote result is being finalized.';
  if (prompt.includes('mission')) return 'Keep moving on your mission.';
  return 'AI MOYA is watching the situation...';
}

export { chat };
