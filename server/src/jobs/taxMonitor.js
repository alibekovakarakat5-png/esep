/**
 * Tax Monitor v2 — автоматическое обновление налоговых ставок
 *
 * 1. Парсит mybuh.kz и kgd.gov.kz на ключевые слова
 * 2. Если находит конкретные числа (МРП, МЗП и т.д.) — сверяет с базой
 * 3. Автоматически обновляет tax_config в базе
 * 4. Отправляет в Telegram: что изменилось + ссылка-пруф + кнопки подтвердить/откатить
 *
 * Источники:
 *   - mybuh.kz — бухгалтерские новости Казахстана
 *   - kgd.gov.kz — КГД МФ РК
 *
 * Запуск: каждые 6 часов через setInterval (вызывается из index.js)
 */

const https = require('https');
const http  = require('http');
const db    = require('../db');
const tg    = require('../bot/telegram');

// ── Ключевые слова для обнаружения изменений ──────────────────────────────────
const TAX_KEYWORDS = [
  'мрп', 'мзп', 'опв', 'опвр', 'восмс', 'осмс', 'ипн', 'ндс',
  'упрощённая декларация', 'форма 910', 'социальные отчисления',
  'пенсионный взнос', 'изменения в налоговый кодекс', 'поправки нк рк',
  'минимальный расчётный показатель', 'минимальная заработная плата',
  'единый совокупный платёж', 'налоговые ставки',
];

// ── Паттерны для извлечения конкретных значений из текста ──────────────────────
const VALUE_PATTERNS = [
  {
    key: 'mrp',
    label: 'МРП',
    patterns: [
      /мрп\s*(?:в\s*\d{4}\s*(?:году?)?\s*)?(?:составит|составляет|равен|равна|=|—|–|-|:)\s*([\d\s]+)\s*(?:тенге|тг|₸)/gi,
      /минимальный\s+расчётный\s+показатель\s*(?:в\s*\d{4}\s*(?:году?)?\s*)?(?:составит|составляет|равен|=|—|–|-|:)\s*([\d\s]+)\s*(?:тенге|тг|₸)/gi,
      /мрп\s*(?:на\s*\d{4}\s*год\s*)?(?:—|–|-|:)\s*([\d\s]+)\s*(?:тенге|тг|₸)/gi,
    ],
    validate: (v) => v >= 3000 && v <= 10000, // разумный диапазон МРП
  },
  {
    key: 'mzp',
    label: 'МЗП',
    patterns: [
      /мзп\s*(?:в\s*\d{4}\s*(?:году?)?\s*)?(?:составит|составляет|равен|равна|=|—|–|-|:)\s*([\d\s]+)\s*(?:тенге|тг|₸)/gi,
      /минимальная\s+заработная\s+плата\s*(?:в\s*\d{4}\s*(?:году?)?\s*)?(?:составит|составляет|=|—|–|-|:)\s*([\d\s]+)\s*(?:тенге|тг|₸)/gi,
      /мзп\s*(?:на\s*\d{4}\s*год\s*)?(?:—|–|-|:)\s*([\d\s]+)\s*(?:тенге|тг|₸)/gi,
    ],
    validate: (v) => v >= 50000 && v <= 200000,
  },
  {
    key: 'vat_rate',
    label: 'НДС ставка',
    patterns: [
      /ндс\s*(?:составит|составляет|повышается до|увеличивается до|=|—|–|-|:)\s*(\d{1,2})\s*%/gi,
      /ставка\s+ндс\s*(?:—|–|-|:)\s*(\d{1,2})\s*%/gi,
    ],
    transform: (v) => v / 100, // 16% → 0.16
    validate: (v) => v >= 10 && v <= 25,
  },
  {
    key: 'opv_rate',
    label: 'ОПВ ставка',
    patterns: [
      /опв\s*(?:составит|составляет|=|—|–|-|:)\s*(\d{1,2})\s*%/gi,
      /обязательные\s+пенсионные\s+взносы\s*(?:—|–|-|:)\s*(\d{1,2})\s*%/gi,
    ],
    transform: (v) => v / 100,
    validate: (v) => v >= 5 && v <= 15,
  },
  {
    key: 'opvr_rate',
    label: 'ОПВР ставка',
    patterns: [
      /опвр\s*(?:составит|составляет|=|—|–|-|:)\s*(\d+[.,]?\d*)\s*%/gi,
    ],
    transform: (v) => v / 100,
    validate: (v) => v >= 1 && v <= 10,
  },
  {
    key: 'vosms_rate_self',
    label: 'ВОСМС ставка',
    patterns: [
      /восмс\s*(?:за\s*себя\s*)?(?:составит|составляет|=|—|–|-|:)\s*(\d+[.,]?\d*)\s*%/gi,
    ],
    transform: (v) => v / 100,
    validate: (v) => v >= 1 && v <= 10,
  },
];

// ── Источники для мониторинга ─────────────────────────────────────────────────
const SOURCES = [
  { name: 'mybuh.kz',   url: 'https://mybuh.kz/news/',                 proto: https },
  { name: 'kgd.gov.kz', url: 'https://kgd.gov.kz/ru/content/novosti', proto: https },
];

// ── Загрузить страницу ────────────────────────────────────────────────────────
function fetchPage(url, proto) {
  return new Promise((resolve) => {
    const req = proto.get(url, { timeout: 10000 }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        const loc = res.headers.location;
        return fetchPage(loc, loc.startsWith('https') ? https : http).then(resolve);
      }
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { body += chunk; if (body.length > 300_000) res.destroy(); });
      res.on('end', () => resolve(body));
    });
    req.on('error', () => resolve(''));
    req.on('timeout', () => { req.destroy(); resolve(''); });
  });
}

// ── Подсчитать ключевые слова ─────────────────────────────────────────────────
function countKeywords(text) {
  const lower = text.toLowerCase();
  let total = 0;
  for (const kw of TAX_KEYWORDS) {
    let pos = 0;
    while ((pos = lower.indexOf(kw, pos)) !== -1) { total++; pos += kw.length; }
  }
  return total;
}

// ── Извлечь конкретные значения из текста ─────────────────────────────────────
function extractValues(text) {
  const found = {};
  const lower = text.toLowerCase();

  for (const vp of VALUE_PATTERNS) {
    for (const regex of vp.patterns) {
      regex.lastIndex = 0; // reset global regex
      let match;
      while ((match = regex.exec(lower)) !== null) {
        const rawStr = match[1].replace(/\s/g, '').replace(',', '.');
        const raw = parseFloat(rawStr);
        if (isNaN(raw)) continue;
        if (vp.validate && !vp.validate(raw)) continue;

        const value = vp.transform ? vp.transform(raw) : raw;
        found[vp.key] = { value: String(value), label: vp.label, raw };
      }
    }
  }

  return found;
}

// ── Состояние: храним последнее кол-во упоминаний per source ─────────────────
const lastCounts = {};

// ── Прочитать текущие значения из базы ────────────────────────────────────────
async function getCurrentConfig() {
  const { rows } = await db.query('SELECT key, value, label FROM tax_config');
  const config = {};
  for (const r of rows) config[r.key] = { value: r.value, label: r.label };
  return config;
}

// ── Сохранить старые значения для возможного отката ───────────────────────────
let lastAutoUpdate = null;

// ── Основная проверка + авто-обновление ───────────────────────────────────────
async function checkTaxSources() {
  const adminUrl = process.env.ADMIN_URL ?? 'https://api.esepkz.com';
  let totalNew = 0;
  const allExtracted = {};
  const proofSources = [];

  for (const src of SOURCES) {
    try {
      const text  = await fetchPage(src.url, src.proto);
      const count = countKeywords(text);
      const prev  = lastCounts[src.name] ?? count;

      if (count > prev + 2) {
        totalNew += (count - prev);
        console.log(`[taxMonitor] ${src.name}: mentions ${prev} → ${count}`);
      }
      lastCounts[src.name] = count;

      // Извлечь конкретные значения
      const values = extractValues(text);
      if (Object.keys(values).length > 0) {
        proofSources.push({ title: src.name, url: src.url });
        Object.assign(allExtracted, values);
      }
    } catch (e) {
      console.error(`[taxMonitor] Error fetching ${src.name}:`, e.message);
    }
  }

  // ── Авто-обновление: сверяем найденные значения с текущими в базе ──────────
  if (Object.keys(allExtracted).length > 0) {
    try {
      const currentConfig = await getCurrentConfig();
      const changes = [];
      const revertData = {};

      for (const [key, extracted] of Object.entries(allExtracted)) {
        const current = currentConfig[key];
        if (!current) continue;

        // Сравниваем значения
        if (current.value !== extracted.value) {
          changes.push({
            key,
            label: extracted.label || current.label,
            oldValue: current.value,
            newValue: extracted.value,
          });
          revertData[key] = current.value;
        }
      }

      if (changes.length > 0) {
        // Обновляем в базе
        for (const c of changes) {
          await db.query(
            'UPDATE tax_config SET value = $1, updated_at = NOW() WHERE key = $2',
            [c.newValue, c.key],
          );
        }

        // Сохраняем данные для отката
        lastAutoUpdate = { changes, revertData, timestamp: Date.now() };

        console.log(`[taxMonitor] Auto-updated ${changes.length} tax config value(s):`,
          changes.map(c => `${c.key}: ${c.oldValue} → ${c.newValue}`).join(', '));

        // Отправляем пруф в Telegram
        tg.notifyTaxAutoUpdate({ changes, sources: proofSources, adminUrl });
        return; // уже отправили детальное уведомление
      }
    } catch (e) {
      console.error('[taxMonitor] Auto-update error:', e.message);
    }
  }

  // Если конкретных изменений не нашли, но упоминания выросли — общее уведомление
  if (totalNew > 2) {
    console.log(`[taxMonitor] Significant tax change activity detected (${totalNew} new mentions)`);
    tg.notifyTaxCheck({ mentions: totalNew, adminUrl });
  }
}

// ── Откат последнего авто-обновления ──────────────────────────────────────────
async function revertLastAutoUpdate() {
  if (!lastAutoUpdate) return { ok: false, error: 'Нечего откатывать' };

  const { revertData, changes } = lastAutoUpdate;
  for (const [key, value] of Object.entries(revertData)) {
    await db.query(
      'UPDATE tax_config SET value = $1, updated_at = NOW() WHERE key = $2',
      [value, key],
    );
  }

  const reverted = changes.map(c => `${c.label}: ${c.newValue} → ${c.oldValue}`);
  lastAutoUpdate = null;

  console.log(`[taxMonitor] Reverted ${reverted.length} value(s)`);
  tg.sendAdmin(
    `↩️ <b>Откат выполнен</b>\n\n` +
    reverted.map(r => `• ${r}`).join('\n'),
  );

  return { ok: true, reverted };
}

// ── Ежемесячные напоминания ───────────────────────────────────────────────────
function checkMonthlyReminder() {
  const adminUrl = process.env.ADMIN_URL ?? 'https://api.esepkz.com';
  const now   = new Date();
  const day   = now.getDate();
  const month = now.getMonth() + 1;

  if (day === 1 && [11, 12, 1, 4].includes(month)) {
    tg.sendMonthlyReminder({ month, adminUrl });
  }
}

// ── Запустить мониторинг ──────────────────────────────────────────────────────
function startMonitor() {
  if (!process.env.TELEGRAM_BOT_TOKEN) {
    console.log('[taxMonitor] TELEGRAM_BOT_TOKEN not set — monitor disabled');
    return;
  }

  setTimeout(() => {
    checkTaxSources();
    checkMonthlyReminder();
  }, 30_000);

  setInterval(() => {
    checkTaxSources();
    checkMonthlyReminder();
  }, 6 * 60 * 60 * 1_000);

  console.log('[taxMonitor] v2 Started — auto-update enabled, checking every 6 hours');
}

module.exports = { startMonitor, checkTaxSources, revertLastAutoUpdate };
