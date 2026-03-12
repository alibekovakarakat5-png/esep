/**
 * Tax Monitor — периодически проверяет сайты на изменения налоговых ставок
 * и уведомляет администратора через Telegram.
 *
 * Источники:
 *   - mybuh.kz — бухгалтерские новости Казахстана
 *   - egov.kz  — официальные документы
 *   - kgd.gov.kz — КГД МФ РК
 *
 * Запуск: каждые 6 часов через setInterval (вызывается из index.js)
 */

const https = require('https');
const http  = require('http');
const tg    = require('../bot/telegram');

// Ключевые слова, указывающие на изменение налогов/соцплатежей
const TAX_KEYWORDS = [
  'мрп', 'мзп', 'опв', 'опвр', 'восмс', 'осмс', 'ипн', 'ндс',
  'упрощённая декларация', 'форма 910', 'социальные отчисления',
  'пенсионный взнос', 'изменения в налоговый кодекс', 'поправки нк рк',
  'минимальный расчётный показатель', 'минимальная заработная плата',
  'единый совокупный платёж', 'налоговые ставки',
];

// Источники для мониторинга
const SOURCES = [
  {
    name:  'mybuh.kz',
    url:   'https://mybuh.kz/news/',
    proto: https,
  },
  {
    name:  'kgd.gov.kz',
    url:   'https://kgd.gov.kz/ru/content/novosti',
    proto: https,
  },
];

// ── Загрузить страницу и вернуть текст ────────────────────────────────────────
function fetchPage(url, proto) {
  return new Promise((resolve) => {
    const req = proto.get(url, { timeout: 10000 }, (res) => {
      // Follow one redirect
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        const loc = res.headers.location;
        const isHttps = loc.startsWith('https');
        return fetchPage(loc, isHttps ? https : http).then(resolve);
      }
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { body += chunk; if (body.length > 200_000) res.destroy(); });
      res.on('end', () => resolve(body.toLowerCase()));
    });
    req.on('error', () => resolve(''));
    req.on('timeout', () => { req.destroy(); resolve(''); });
  });
}

// ── Подсчитать упоминания ключевых слов ──────────────────────────────────────
function countKeywords(text) {
  let total = 0;
  for (const kw of TAX_KEYWORDS) {
    let pos = 0;
    while ((pos = text.indexOf(kw, pos)) !== -1) { total++; pos += kw.length; }
  }
  return total;
}

// ── Состояние: храним последнее кол-во упоминаний per source ─────────────────
const lastCounts = {};

// ── Основная проверка ─────────────────────────────────────────────────────────
async function checkTaxSources() {
  const adminUrl = process.env.ADMIN_URL ?? 'https://esep-production.up.railway.app';
  let totalNew = 0;

  for (const src of SOURCES) {
    try {
      const text  = await fetchPage(src.url, src.proto);
      const count = countKeywords(text);
      const prev  = lastCounts[src.name] ?? count; // first run: baseline

      if (count > prev + 2) {   // threshold: +3 новых упоминания → считаем значимым
        totalNew += (count - prev);
        console.log(`[taxMonitor] ${src.name}: mentions ${prev} → ${count}`);
      }
      lastCounts[src.name] = count;
    } catch (e) {
      console.error(`[taxMonitor] Error fetching ${src.name}:`, e.message);
    }
  }

  if (totalNew > 2) {
    console.log(`[taxMonitor] Significant tax change activity detected (${totalNew} new mentions)`);
    tg.notifyTaxCheck({ mentions: totalNew, adminUrl });
  }
}

// ── Ежемесячные напоминания ───────────────────────────────────────────────────
function checkMonthlyReminder() {
  const adminUrl = process.env.ADMIN_URL ?? 'https://esep-production.up.railway.app';
  const now   = new Date();
  const day   = now.getDate();
  const month = now.getMonth() + 1; // 1-12

  // Отправляем в 1-й день месяца для ноябрь/декабрь/январь/апрель
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

  // Первая проверка через 30 сек после старта (дать серверу прогреться)
  setTimeout(() => {
    checkTaxSources();
    checkMonthlyReminder();
  }, 30_000);

  // Затем каждые 6 часов
  setInterval(() => {
    checkTaxSources();
    checkMonthlyReminder();
  }, 6 * 60 * 60 * 1_000);

  console.log('[taxMonitor] Started — checking every 6 hours');
}

module.exports = { startMonitor, checkTaxSources };
