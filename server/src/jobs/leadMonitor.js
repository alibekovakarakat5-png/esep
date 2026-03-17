/**
 * Lead Monitor — ежедневно парсит публичные Telegram-каналы, форумы и
 * data.egov.kz на предмет потенциальных лидов для Esep.
 *
 * Результат: дайджест в приватный Telegram-канал.
 *
 * Запуск: раз в 24 часа (9:00 по Алматы = 03:00 UTC)
 */

const https = require('https');
const http  = require('http');
const db    = require('../db');
const tg    = require('../bot/telegram');

// ── Telegram-каналы для мониторинга (публичные посты через t.me/s/) ──────────

const TG_CHANNELS = [
  { name: 'Учет.KZ',         slug: 'uchet_kz' },
  { name: 'MyBuh.kz',        slug: 'mybuh_kz' },
  { name: 'ProНалоги',       slug: 'salyqtezinfo' },
  { name: 'ПАРАГРАФ',        slug: 'prg_buh' },
  { name: 'PRO1C.kz',        slug: 'pro1ckz' },
  { name: 'РЦПП ИНФО',      slug: 'rcppkz' },
  { name: 'Atameken Business', slug: 'atamekenbusiness' },
  { name: 'КГД МФ РК',       slug: 'kgdmfrk' },
  { name: 'inbusiness.kz',    slug: 'inbusinesskz' },
];

// ── Ключевые слова для поиска лидов ──────────────────────────────────────────

const LEAD_KEYWORDS = [
  // Прямой спрос
  'ищу приложение', 'ищу программу', 'какое приложение', 'какую программу',
  'альтернатива 1с', 'замена 1с', 'вместо 1с',
  'приложение для ип', 'приложение для бухгалтер',
  'программа для ип', 'автоматизация учёта', 'автоматизация учета',
  'онлайн бухгалтерия', 'мобильная бухгалтерия',
  // Боли ЦА
  'штраф за несдачу', 'забыл сдать 910', 'просрочил декларацию',
  'как заполнить 910', 'не могу заполнить', 'помогите с формой',
  'e-salyq не работает', 'e-salyq баг', 'esalyq ошибка',
  'касpi выписка', 'как скачать выписку', 'импорт выписки',
  // Регистрация бизнеса
  'открыл ип', 'зарегистрировал ип', 'открыть тоо', 'регистрация ип',
  'только открыл ип', 'начинающий ип', 'новый ип',
  // Дедлайны
  'когда сдавать 910', 'срок сдачи', 'дедлайн налог',
  'полугодовая декларация', 'форма 910.00',
];

// Слова-маркеры высокого интента
const HIGH_INTENT = [
  'ищу приложение', 'ищу программу', 'какое приложение', 'какую программу',
  'альтернатива 1с', 'замена 1с', 'приложение для ип',
  'e-salyq не работает', 'открыл ип', 'зарегистрировал ип',
];

// ── Веб-страницы для мониторинга ─────────────────────────────────────────────

const WEB_SOURCES = [
  { name: 'forum.zakon.kz',  url: 'https://forum.zakon.kz/forum/209-%D1%84%D0%BE%D1%80%D1%83%D0%BC-%D0%B1%D1%83%D1%85%D0%B3%D0%B0%D0%BB%D1%82%D0%B5%D1%80%D0%BE%D0%B2/' },
  { name: 'mybuh.kz/news',   url: 'https://mybuh.kz/news/' },
  { name: 'kgd.gov.kz',      url: 'https://kgd.gov.kz/ru/content/novosti' },
];

// ── data.egov.kz — новые ИП ─────────────────────────────────────────────────

const EGOV_API = 'https://data.egov.kz/api/v4/gbd_ul/v2';

// ── Утилиты ──────────────────────────────────────────────────────────────────

function fetchPage(url) {
  const proto = url.startsWith('https') ? https : http;
  return new Promise((resolve) => {
    const req = proto.get(url, { timeout: 15000, headers: { 'User-Agent': 'Esep-LeadMonitor/1.0' } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return fetchPage(res.headers.location).then(resolve);
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

function extractTgPosts(html) {
  // t.me/s/ returns HTML with .tgme_widget_message_text divs
  const posts = [];
  const regex = /class="tgme_widget_message_text[^"]*"[^>]*>([\s\S]*?)<\/div>/gi;
  let match;
  while ((match = regex.exec(html)) !== null) {
    // Strip HTML tags
    const text = match[1].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
    if (text.length > 20) posts.push(text);
  }
  return posts;
}

function findKeywordMatches(text) {
  const lower = text.toLowerCase();
  const found = [];
  for (const kw of LEAD_KEYWORDS) {
    if (lower.includes(kw)) found.push(kw);
  }
  return found;
}

function isHighIntent(keywords) {
  return keywords.some(kw => HIGH_INTENT.includes(kw));
}

// ── Парсинг Telegram-каналов ─────────────────────────────────────────────────

async function scanTelegramChannels() {
  const results = [];

  for (const ch of TG_CHANNELS) {
    try {
      const html = await fetchPage(`https://t.me/s/${ch.slug}`);
      const posts = extractTgPosts(html);

      for (const post of posts) {
        const matches = findKeywordMatches(post);
        if (matches.length > 0) {
          results.push({
            source: `TG @${ch.slug}`,
            sourceName: ch.name,
            text: post.substring(0, 300),
            keywords: matches,
            highIntent: isHighIntent(matches),
          });
        }
      }
    } catch (e) {
      console.error(`[leadMonitor] Error scanning @${ch.slug}:`, e.message);
    }
  }

  return results;
}

// ── Парсинг веб-страниц ─────────────────────────────────────────────────────

async function scanWebSources() {
  const results = [];

  for (const src of WEB_SOURCES) {
    try {
      const html = await fetchPage(src.url);
      const text = html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');

      // Extract snippets around keyword matches
      const lower = text.toLowerCase();
      for (const kw of LEAD_KEYWORDS) {
        let pos = 0;
        while ((pos = lower.indexOf(kw, pos)) !== -1) {
          const start = Math.max(0, pos - 80);
          const end = Math.min(text.length, pos + kw.length + 120);
          const snippet = text.substring(start, end).trim();
          results.push({
            source: src.name,
            sourceName: src.name,
            text: `...${snippet}...`,
            keywords: [kw],
            highIntent: isHighIntent([kw]),
          });
          pos += kw.length + 200; // skip ahead to avoid duplicates
        }
      }
    } catch (e) {
      console.error(`[leadMonitor] Error scanning ${src.name}:`, e.message);
    }
  }

  // Deduplicate
  const seen = new Set();
  return results.filter(r => {
    const key = r.text.substring(0, 100);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// ── Проверка новых ИП через data.egov.kz ─────────────────────────────────────

async function checkNewBusinesses() {
  try {
    // Try to get count of recently registered businesses
    const html = await fetchPage('https://data.egov.kz/datasets/view?index=gbd_ul');
    const match = html.match(/(\d[\d\s,]+)\s*(записей|records)/i);
    const count = match ? match[1].replace(/\s/g, '') : null;
    return count ? parseInt(count, 10) : null;
  } catch (e) {
    console.error('[leadMonitor] Error checking egov:', e.message);
    return null;
  }
}

// ── Загрузить ключевые слова из БД (дополнительные) ──────────────────────────

async function loadDbKeywords() {
  try {
    const { rows } = await db.query('SELECT keyword FROM lead_keywords');
    for (const row of rows) {
      const kw = row.keyword.toLowerCase();
      if (!LEAD_KEYWORDS.includes(kw)) LEAD_KEYWORDS.push(kw);
    }
  } catch (e) {
    // DB keywords are optional
  }
}

// ── Сохранить статистику в БД ────────────────────────────────────────────────

async function saveStats(stats) {
  try {
    await db.query(`
      CREATE TABLE IF NOT EXISTS lead_monitor_log (
        id         SERIAL PRIMARY KEY,
        run_date   DATE NOT NULL DEFAULT CURRENT_DATE,
        tg_leads   INT DEFAULT 0,
        web_leads  INT DEFAULT 0,
        high_intent INT DEFAULT 0,
        egov_total  BIGINT,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    await db.query(
      `INSERT INTO lead_monitor_log (tg_leads, web_leads, high_intent, egov_total)
       VALUES ($1, $2, $3, $4)`,
      [stats.tgLeads, stats.webLeads, stats.highIntent, stats.egovTotal]
    );
  } catch (e) {
    console.error('[leadMonitor] Error saving stats:', e.message);
  }
}

// ── Форматирование дайджеста ─────────────────────────────────────────────────

function formatDigest(tgResults, webResults, egovTotal) {
  const now = new Date();
  const dateStr = now.toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' });

  const highIntentTg = tgResults.filter(r => r.highIntent);
  const highIntentWeb = webResults.filter(r => r.highIntent);
  const totalHigh = highIntentTg.length + highIntentWeb.length;

  let msg = `<b>Lead Monitor — ${dateStr}</b>\n\n`;

  // Summary
  msg += `<b>Итого:</b>\n`;
  msg += `• Telegram: ${tgResults.length} упоминаний\n`;
  msg += `• Форумы/сайты: ${webResults.length} упоминаний\n`;
  msg += `• Высокий интент: ${totalHigh}\n`;
  if (egovTotal) msg += `• ИП/ТОО в реестре: ${egovTotal.toLocaleString('ru-RU')}\n`;
  msg += `\n`;

  // High intent leads (most valuable)
  if (totalHigh > 0) {
    msg += `<b>Горячие лиды:</b>\n`;
    const allHigh = [...highIntentTg, ...highIntentWeb].slice(0, 10);
    for (const r of allHigh) {
      const kwStr = r.keywords.slice(0, 3).join(', ');
      msg += `\n<b>${r.source}</b> [${kwStr}]\n`;
      msg += `<i>${r.text.substring(0, 200)}</i>\n`;
    }
    msg += `\n`;
  }

  // Regular mentions by source
  if (tgResults.length > 0) {
    msg += `<b>Telegram-каналы:</b>\n`;
    const bySource = {};
    for (const r of tgResults) {
      bySource[r.sourceName] = (bySource[r.sourceName] || 0) + 1;
    }
    for (const [name, count] of Object.entries(bySource)) {
      msg += `• ${name}: ${count} упоминаний\n`;
    }
    msg += `\n`;
  }

  if (webResults.length > 0) {
    msg += `<b>Форумы/сайты:</b>\n`;
    const bySource = {};
    for (const r of webResults) {
      bySource[r.sourceName] = (bySource[r.sourceName] || 0) + 1;
    }
    for (const [name, count] of Object.entries(bySource)) {
      msg += `• ${name}: ${count} упоминаний\n`;
    }
    msg += `\n`;
  }

  // Top keywords
  const allResults = [...tgResults, ...webResults];
  const kwCounts = {};
  for (const r of allResults) {
    for (const kw of r.keywords) {
      kwCounts[kw] = (kwCounts[kw] || 0) + 1;
    }
  }
  const topKw = Object.entries(kwCounts).sort((a, b) => b[1] - a[1]).slice(0, 10);
  if (topKw.length > 0) {
    msg += `<b>Топ ключевые слова:</b>\n`;
    for (const [kw, count] of topKw) {
      msg += `• "${kw}" — ${count}x\n`;
    }
  }

  return msg;
}

// ── Основная функция ─────────────────────────────────────────────────────────

async function runLeadScan() {
  console.log('[leadMonitor] Starting daily scan...');

  await loadDbKeywords();

  const [tgResults, webResults, egovTotal] = await Promise.all([
    scanTelegramChannels(),
    scanWebSources(),
    checkNewBusinesses(),
  ]);

  console.log(`[leadMonitor] Found: TG=${tgResults.length}, Web=${webResults.length}, High=${tgResults.filter(r => r.highIntent).length + webResults.filter(r => r.highIntent).length}`);

  const digest = formatDigest(tgResults, webResults, egovTotal);

  // Send to private channel
  await tg.sendToPrivate(digest);

  // Save stats
  await saveStats({
    tgLeads: tgResults.length,
    webLeads: webResults.length,
    highIntent: tgResults.filter(r => r.highIntent).length + webResults.filter(r => r.highIntent).length,
    egovTotal,
  });

  console.log('[leadMonitor] Scan complete, digest sent.');
}

// ── Scheduler ────────────────────────────────────────────────────────────────

function startLeadMonitor() {
  if (!process.env.TELEGRAM_BOT_TOKEN) {
    console.log('[leadMonitor] TELEGRAM_BOT_TOKEN not set — monitor disabled');
    return;
  }

  // Calculate delay until next 03:00 UTC (09:00 Almaty)
  function msUntilNext0300() {
    const now = new Date();
    const target = new Date(now);
    target.setUTCHours(3, 0, 0, 0);
    if (target <= now) target.setUTCDate(target.getUTCDate() + 1);
    return target - now;
  }

  // First run: 60 sec after start (to let server warm up)
  setTimeout(() => {
    runLeadScan().catch(e => console.error('[leadMonitor] Error:', e.message));

    // Then schedule daily at 09:00 Almaty
    setTimeout(function scheduleDaily() {
      runLeadScan().catch(e => console.error('[leadMonitor] Error:', e.message));
      // Schedule next run in ~24h (recalculate to stay on time)
      setTimeout(scheduleDaily, msUntilNext0300());
    }, msUntilNext0300());
  }, 60_000);

  console.log('[leadMonitor] Started — daily at 09:00 Almaty (03:00 UTC)');
}

module.exports = { startLeadMonitor, runLeadScan };
