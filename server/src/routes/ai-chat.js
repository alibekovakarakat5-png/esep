// ── Консультант Esep — RAG + адаптивный стиль ────────────────────────────────
// POST /api/ai-chat
//   body: { messages: [{role,content}], segment?, screen_context?, official_only?, lang? }
//   resp: { reply, citations: [...], detected_level, follow_up?, usage }
// POST /api/ai-chat/feedback
//   body: { answer_id, feedback: 'helpful'|'not_helpful', note? }

const express = require('express');
const router  = express.Router();
const db      = require('../db');

const { retrieve } = require('../services/knowledge_retrieval');

// ── LLM provider (Groq) ──────────────────────────────────────────────────────

const GROQ_API_KEY = process.env.GROQ_API_KEY;
const GROQ_MODEL   = process.env.GROQ_MODEL || 'llama-3.3-70b-versatile';
const GROQ_URL     = 'https://api.groq.com/openai/v1/chat/completions';

// ── Базовая фактологическая шпаргалка (constant 2026) ────────────────────────
// Используется как "always-on" контекст: даже без RAG модель знает ставки.

const FACT_SHEET = `
═══ КОНСТАНТЫ 2026 (Закон 214-VIII НК РК) ═══
• МРП = 4 325 ₸ • МЗП = 85 000 ₸
• 910 (упрощёнка): 4% от дохода (100% ИПН, СН=0%). Лимит 600 000 МРП/год.
• ОУР ИПН: 10% до 8 500 МРП/год, 15% выше. Базовый вычет 30 МРП/мес.
• НДС: 16%. Порог регистрации 10 000 МРП.
• ОПВ 10% от 1 МЗП • ОПВР 3.5% • СО 5% от 1 МЗП • ВОСМС "за себя" 5% от 1.4 МЗП
• Сотрудник: ОПВ 10%, ВОСМС 2% (база до 20 МЗП). Работодатель: ОПВР 3.5%, СО 5%, ООСМС 3% (база до 40 МЗП).
• ТОО: КПН 20%, СН 6% от ФОТ, налог на дивиденды 5/10%, малый бизнес КПН 0% (до 2028).

═══ ДЕДЛАЙНЫ ═══
• 910 за 1-е полугодие: подать 15 авг, оплатить 25 авг
• 910 за 2-е полугодие: подать 15 фев, оплатить 25 фев
• Соцплатежи: до 25 числа след. месяца
• 200 (ИПН/СН за сотрудников): ежеквартально, до 15 числа 2-го месяца
• 100 (КПН ТОО): до 31 марта след. года
• 300 (НДС): ежеквартально, до 15 числа 2-го месяца
• 2-МП (стат): до 25 числа после квартала
`.trim();

// ── Промпт-каркас с адаптивным стилем ────────────────────────────────────────

const TONE_INSTRUCTIONS = {
  newbie: `
СТИЛЬ ОТВЕТА: пользователь — новичок, не разбирается в терминах.
- Отвечай простыми словами, как будто объясняешь другу.
- Каждый специальный термин (ИПН, ОПВ, ВОСМС, КБК и т.д.) обязательно поясняй в скобках.
  Пример: "ИПН (это налог с дохода) платится...".
- Используй короткие предложения и пошаговые объяснения.
- В конце ответа кратко резюмируй "Что вам делать сейчас:" с 2-3 простыми шагами.
- Избегай юридических формулировок, переводи их на бытовой язык.
`,
  intermediate: `
СТИЛЬ ОТВЕТА: пользователь немного разбирается в учёте.
- Используй термины, но при первом упоминании коротко поясняй (одной фразой).
- Давай прямые ответы с цифрами и расчётами.
- В конце добавь "Что важно учесть:" с практическими нюансами.
`,
  expert: `
СТИЛЬ ОТВЕТА: пользователь — профессионал (бухгалтер).
- Используй терминологию свободно, без расшифровок.
- Будь лаконичным, формулировки деловые.
- Указывай номера статей, пунктов, дат.
- Не объясняй очевидные для бухгалтера вещи.
`,
};

const SEGMENT_CONTEXT = {
  ip_solo:    'Пользователь — ИП без сотрудников на упрощёнке (910). Его волнует свой налог и платежи "за себя".',
  ip_emp:     'Пользователь — ИП с сотрудниками. Его волнует и личные платежи, и зарплатные налоги (форма 200).',
  too:        'Пользователь — представитель ТОО. Его волнует КПН, НДС, ЭСФ, зарплатные налоги, дивиденды.',
  accountant: 'Пользователь — бухгалтер на аутсорсе. Ведёт нескольких клиентов (ИП и ТОО). Ждёт лаконичный профессиональный ответ.',
  unknown:    'Сегмент пользователя не определён.',
};

function buildSystemPrompt({ segment, level, screenContext, retrievedChunks, officialOnly }) {
  const tone    = TONE_INSTRUCTIONS[level] || TONE_INSTRUCTIONS.intermediate;
  const segCtx  = SEGMENT_CONTEXT[segment]  || SEGMENT_CONTEXT.unknown;

  const sourcesBlock = retrievedChunks.length
    ? retrievedChunks.map((c, i) => {
        const src = c.sourceType === 'esep_platform'
          ? `Esep платформа: ${c.title}`
          : c.sourceType === 'law'
            ? `${c.title} (${c.metadata?.law_full_name || 'НК РК'})`
            : `${c.title} (${c.url})`;
        return `[#${i + 1}] ${src}\n${c.text}`;
      }).join('\n\n---\n\n')
    : '(источники не найдены, отвечай только на основе общих знаний из FACT SHEET ниже)';

  return `Ты — Консультант Esep. Ты помогаешь предпринимателям и бухгалтерам Казахстана с налогами, учётом и работой в приложении Esep.

═══ КТО ПЕРЕД ТОБОЙ ═══
${segCtx}
${screenContext ? `Сейчас на экране: ${screenContext}` : ''}

═══ ${tone.trim()} ═══

═══ ГЛАВНЫЕ ПРАВИЛА ═══
1. Отвечай ТОЛЬКО на основе блока ИСТОЧНИКИ ниже + FACT SHEET.
2. Если в источниках нет ответа — честно скажи "В моих источниках нет точного ответа, рекомендую уточнить у налогового консультанта или в КГД через cabinet.salyk.kz". НЕ ВЫДУМЫВАЙ.
3. Каждое важное утверждение помечай ссылкой на источник в формате [#N], где N — номер из блока ИСТОЧНИКИ.
4. Если вопрос про работу в приложении Esep — обязательно подскажи конкретные шаги: куда нажать, в какой раздел зайти. Используй источники типа "Esep платформа".
5. Заканчивай ответ строкой META JSON в одну строку:
   META {"detected_level":"newbie|intermediate|expert","cited":[N1,N2,...],"follow_up":["вопрос1","вопрос2","вопрос3"],"confidence":0.0-1.0}
6. ${officialOnly ? 'Используй ТОЛЬКО официальные источники (НК РК, письма КГД).' : 'Можешь использовать любые источники, но официальные приоритетнее.'}
7. Все суммы — с пробелами и валютой (например, 1 250 000 ₸).
8. Отвечай на языке пользователя (русский или казахский).

═══ ИСТОЧНИКИ ═══
${sourcesBlock}

═══ FACT SHEET (всегда актуально на 2026) ═══
${FACT_SHEET}`;
}

// ── Детектор уровня пользователя ─────────────────────────────────────────────

const TERM_TOKENS = [
  'ипн', 'опв', 'опвр', 'восмс', 'оосмс', 'со', 'сн ', 'кбк',
  'кпн', 'ндс', 'эсф', 'фно', 'снр', 'фот', 'оур',
  'проводка', 'дебет', 'кредит', 'регистр', 'контрагент',
  'налоговая база', 'оборот', 'маслихат', 'лицевой счёт',
  '910', '200.00', '300.00', '100.00', '700.00', '101110', '101111',
];

const STRUGGLE_PHRASES = [
  'не понимаю', 'не знаю', 'что это', 'что такое',
  'помогите', 'запутался', 'запуталась', 'объясните', 'объясни',
  'как это', 'не разбираюсь', 'не понятно', 'непонятно',
];

function detectLevel({ messages, segment, savedLevel }) {
  // Бухгалтер по умолчанию — expert
  if (segment === 'accountant') return 'expert';

  const userMessages = messages.filter(m => m.role === 'user').slice(-5);
  const text = userMessages.map(m => (m.content || '').toLowerCase()).join(' ');
  if (!text.trim()) return savedLevel || 'newbie';

  const usesTerms     = TERM_TOKENS.some(t => text.includes(t));
  const asksStruggle  = STRUGGLE_PHRASES.some(t => text.includes(t));

  let level;
  if (usesTerms && !asksStruggle) level = (segment === 'too') ? 'expert' : 'intermediate';
  else if (usesTerms &&  asksStruggle) level = 'intermediate';
  else if (!usesTerms && asksStruggle) level = 'newbie';
  else level = savedLevel || (segment === 'ip_solo' ? 'newbie' : 'intermediate');

  return level;
}

// ── Профиль пользователя ─────────────────────────────────────────────────────

async function loadOrCreateProfile(userId) {
  if (!userId || userId === 'anon') return { detected_level: 'newbie', message_count: 0 };
  try {
    const r = await db.query(
      `SELECT detected_level, uses_terms, asks_struggle, message_count, preferred_tone
         FROM user_consultant_profile
        WHERE user_id = $1`,
      [userId]
    );
    if (r.rows.length === 0) {
      await db.query(
        `INSERT INTO user_consultant_profile (user_id) VALUES ($1)
         ON CONFLICT DO NOTHING`,
        [userId]
      );
      return { detected_level: 'newbie', message_count: 0 };
    }
    return r.rows[0];
  } catch {
    return { detected_level: 'newbie', message_count: 0 };
  }
}

async function updateProfile(userId, { detectedLevel, messages }) {
  if (!userId || userId === 'anon') return;
  const text = messages.filter(m => m.role === 'user').map(m => m.content).join(' ').toLowerCase();
  const usesTerms    = TERM_TOKENS.some(t => text.includes(t));
  const asksStruggle = STRUGGLE_PHRASES.some(t => text.includes(t));
  try {
    await db.query(
      `INSERT INTO user_consultant_profile
         (user_id, detected_level, uses_terms, asks_struggle, message_count, last_message_at, updated_at)
       VALUES ($1, $2, $3, $4, 1, NOW(), NOW())
       ON CONFLICT (user_id) DO UPDATE
         SET detected_level   = $2,
             uses_terms       = user_consultant_profile.uses_terms OR $3,
             asks_struggle    = user_consultant_profile.asks_struggle OR $4,
             message_count    = user_consultant_profile.message_count + 1,
             last_message_at  = NOW(),
             updated_at       = NOW()`,
      [userId, detectedLevel, usesTerms, asksStruggle]
    );
  } catch (err) {
    console.error('[consultant] profile update failed:', err.message);
  }
}

// ── META парсер ──────────────────────────────────────────────────────────────

function extractMeta(reply) {
  const m = reply.match(/META\s*({[\s\S]*?})\s*$/);
  if (!m) return { cleanReply: reply.trim(), meta: null };
  try {
    const meta = JSON.parse(m[1]);
    const cleanReply = reply.slice(0, m.index).trim();
    return { cleanReply, meta };
  } catch {
    return { cleanReply: reply.trim(), meta: null };
  }
}

function citationsFromMeta(meta, retrieved) {
  if (!meta?.cited || !Array.isArray(meta.cited)) {
    return retrieved.slice(0, 3).map((c, i) => buildCitation(c, i + 1));
  }
  return meta.cited
    .map(n => {
      const idx = parseInt(n, 10) - 1;
      if (idx < 0 || idx >= retrieved.length) return null;
      return buildCitation(retrieved[idx], idx + 1);
    })
    .filter(Boolean);
}

function buildCitation(c, n) {
  const isLaw      = c.sourceType === 'law';
  const isPlatform = c.sourceType === 'esep_platform';
  const quote = (c.text || '').slice(0, 280);
  return {
    n,
    chunk_id: c.chunkId,
    source_id: c.sourceId,
    title: c.title,
    url: isPlatform ? null : c.url,
    source_type: c.sourceType,
    trust_weight: c.trustWeight,
    quote,
    is_law: isLaw,
    is_platform: isPlatform,
    article: c.metadata?.article || null,
    published_at: c.publishedAt,
  };
}

// ── Rate limiting (in-memory) ────────────────────────────────────────────────

const userCounts = new Map();
const MAX_PER_DAY_FREE = 10;
const MAX_PER_DAY_PAID = 100;

function checkLimit(userId, tier) {
  const today = new Date().toISOString().slice(0, 10);
  const key   = `${userId}:${today}`;
  const count = userCounts.get(key) || 0;
  const max   = tier === 'free' ? MAX_PER_DAY_FREE : MAX_PER_DAY_PAID;
  if (count >= max) return false;
  userCounts.set(key, count + 1);
  return true;
}

// ── POST /api/ai-chat ────────────────────────────────────────────────────────

router.post('/', async (req, res) => {
  if (!GROQ_API_KEY) {
    return res.status(503).json({ error: 'Консультант временно недоступен' });
  }

  const startedAt = Date.now();
  const {
    messages,
    segment = 'unknown',
    screen_context = null,
    official_only = false,
  } = req.body;

  if (!messages || !Array.isArray(messages) || messages.length === 0) {
    return res.status(400).json({ error: 'Отправьте массив messages' });
  }

  const userId = req.user?.id || 'anon';
  const tier   = req.user?.tier || 'free';
  if (!checkLimit(userId, tier)) {
    return res.status(429).json({
      error: tier === 'free'
        ? `Лимит ${MAX_PER_DAY_FREE} вопросов/день на бесплатном тарифе. Перейдите на Solo для ${MAX_PER_DAY_PAID} вопросов.`
        : 'Лимит вопросов на сегодня исчерпан.',
    });
  }

  const trimmed = messages.slice(-10).map(m => ({
    role:    m.role === 'user' ? 'user' : 'assistant',
    content: String(m.content || '').slice(0, 2000),
  }));

  const lastUserMsg = [...trimmed].reverse().find(m => m.role === 'user');
  if (!lastUserMsg) return res.status(400).json({ error: 'Нет сообщения пользователя' });

  // ── Профиль и уровень ──────────────────────────────────────────────────────
  const profile = await loadOrCreateProfile(userId);
  const detectedLevel = detectLevel({
    messages: trimmed,
    segment,
    savedLevel: profile.detected_level,
  });

  // ── Retrieval ──────────────────────────────────────────────────────────────
  const audience = segment === 'unknown' ? 'all' : segment;
  let retrieved = [];
  try {
    retrieved = await retrieve({
      query: lastUserMsg.content,
      audience,
      officialOnly: !!official_only,
      topK: 8,
      candidateK: 25,
    });
  } catch (err) {
    console.error('[consultant] retrieval failed:', err.message);
    retrieved = [];
  }

  // ── Формирование промпта и вызов LLM ──────────────────────────────────────
  const systemPrompt = buildSystemPrompt({
    segment,
    level: detectedLevel,
    screenContext: screen_context,
    retrievedChunks: retrieved,
    officialOnly: !!official_only,
  });

  try {
    const response = await fetch(GROQ_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${GROQ_API_KEY}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        model:    GROQ_MODEL,
        messages: [{ role: 'system', content: systemPrompt }, ...trimmed],
        temperature: 0.25,
        max_tokens:  1500,
        top_p:       0.9,
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error('[consultant] Groq error:', response.status, err);
      return res.status(502).json({ error: 'Ошибка Консультанта. Попробуйте позже.' });
    }

    const data = await response.json();
    const rawReply = data.choices?.[0]?.message?.content || 'Не удалось получить ответ.';
    const { cleanReply, meta } = extractMeta(rawReply);
    const citations = citationsFromMeta(meta, retrieved);
    const finalLevel = meta?.detected_level || detectedLevel;
    const followUp   = Array.isArray(meta?.follow_up) ? meta.follow_up.slice(0, 3) : [];
    const confidence = typeof meta?.confidence === 'number' ? meta.confidence : null;

    // ── Лог + профиль (фоном, не блокируем ответ) ─────────────────────────────
    const latencyMs = Date.now() - startedAt;
    let answerId = null;
    try {
      const ins = await db.query(
        `INSERT INTO consultant_answer_log
           (user_id, user_segment, detected_level, screen_context, question, answer,
            citations, retrieval_score, llm_model, latency_ms)
         VALUES ($1, $2, $3, $4::jsonb, $5, $6, $7::jsonb, $8, $9, $10)
         RETURNING id`,
        [
          userId === 'anon' ? null : userId,
          segment,
          finalLevel,
          JSON.stringify(screen_context || {}),
          lastUserMsg.content,
          cleanReply,
          JSON.stringify(citations),
          retrieved[0]?.score || null,
          GROQ_MODEL,
          latencyMs,
        ]
      );
      answerId = ins.rows[0]?.id;
    } catch (err) {
      console.error('[consultant] log insert failed:', err.message);
    }
    updateProfile(userId, { detectedLevel: finalLevel, messages: trimmed }).catch(() => {});

    res.json({
      reply: cleanReply,
      answer_id: answerId,
      citations,
      detected_level: finalLevel,
      follow_up: followUp,
      confidence,
      usage: {
        prompt_tokens:     data.usage?.prompt_tokens,
        completion_tokens: data.usage?.completion_tokens,
        retrieved:         retrieved.length,
        latency_ms:        latencyMs,
      },
    });
  } catch (err) {
    console.error('[consultant] fetch error:', err.message);
    res.status(500).json({ error: 'Ошибка соединения с Консультантом. Попробуйте позже.' });
  }
});

// ── POST /api/ai-chat/feedback ───────────────────────────────────────────────

router.post('/feedback', async (req, res) => {
  const { answer_id, feedback, note } = req.body;
  if (!answer_id || !['helpful', 'not_helpful'].includes(feedback)) {
    return res.status(400).json({ error: 'Невалидные параметры' });
  }
  try {
    await db.query(
      `UPDATE consultant_answer_log
          SET feedback = $1, feedback_note = $2
        WHERE id = $3`,
      [feedback, note || null, answer_id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
