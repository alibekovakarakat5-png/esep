// ── Ingest НК РК (Закон 214-VIII) с adilet.zan.kz ────────────────────────────
//
// Цель: сделать так, чтобы Консультант мог цитировать конкретные статьи Налогового кодекса.
// Стратегия:
//   1. Скачиваем HTML основной страницы документа
//   2. Парсим оглавление + текст статей (на adilet.zan.kz структура: разделы → главы → статьи)
//   3. Каждая статья = один источник (knowledge_source)
//   4. Текст статьи = один или несколько чанков
//   5. anchor = '#z2500000214-st-N' для прямой ссылки
//
// Запуск: node src/jobs/ingestNkRk.js  или  curl -X POST .../api/admin/ingest/nk
//
// ВАЖНО: adilet.zan.kz — публичный сайт государственных НПА.
// По ст. 8 Закона "Об авторском праве и смежных правах" РК
// официальные документы (законы, судебные акты) не охраняются авторским правом.

const https = require('node:https');
const { indexSource } = require('../services/knowledge_indexer');
const { chunkText }   = require('../services/knowledge_indexer');

// adilet.zan.kz отдаёт неполную цепочку TLS без публичного корня — классическая
// мисконфигурация казахстанских госсайтов. Контент — публичные акты, риск MITM
// приемлемый, поэтому делаем relaxed TLS только при запросе на adilet.

function fetchAdilet(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, {
      rejectUnauthorized: false,
      headers: {
        'User-Agent': 'Mozilla/5.0 EsepKZ/1.0 (knowledge indexer; +https://esep.kz)',
        'Accept-Language': 'ru,kk;q=0.9,en;q=0.8',
      },
    }, (res) => {
      // Follow redirects (1 hop)
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        return resolve(fetchAdilet(new URL(res.headers.location, url).href));
      }
      if (res.statusCode !== 200) {
        res.resume();
        return reject(new Error(`adilet.zan.kz HTTP ${res.statusCode}`));
      }
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
      res.on('error', reject);
    });
    req.on('error', reject);
    req.setTimeout(60000, () => req.destroy(new Error('adilet timeout 60s')));
  });
}

const NK_RK_URL = 'https://adilet.zan.kz/rus/docs/K2500000214';
const NK_RK_DOC_NUMBER = 'K2500000214';

// ── Util: clean HTML to plain text ───────────────────────────────────────────

function stripHtml(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n\n')
    .replace(/<\/div>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&laquo;/g, '«')
    .replace(/&raquo;/g, '»')
    .replace(/&mdash;/g, '—')
    .replace(/&ndash;/g, '–')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#171;/g, '«')
    .replace(/&#187;/g, '»')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

// ── Парсер структуры документа adilet.zan.kz ─────────────────────────────────
// Формат: разделы помечены как <p class="rasdel">, главы — <p class="glava">,
// статьи — <p class="statya"> с заголовком, потом текст до следующей статьи.
//
// Если структура изменится — корректируем здесь.

function parseArticles(html) {
  const text = html.replace(/\r/g, '');

  // Структура adilet:
  //   <p><b><a name="zN"></a>Статья X. Название</b></p>
  //   <p id="zN+1">...текст пункта 1...</p>
  //   <p id="zN+2">...текст пункта 2...</p>
  //   <p><b><a name="zN+3"></a>Статья X+1. ...</b></p>  ← следующая
  // Также допустимы заголовки <h3> между статьями.
  //
  // Шаги:
  //   1. Найти все позиции, где встречается паттерн "Статья NUMBER. Title" в <b>
  //   2. Между двумя такими позициями = тело предыдущей статьи (плюс возможные h3)
  //   3. Из тела вырезаем h3 (это Главы/Параграфы/Разделы — попадают в metadata, но не в текст)

  const headerRe = /<p[^>]*>\s*<b>\s*(?:<a\s+name="z\d+"[^>]*><\/a>)?\s*Статья\s+([\d\-\.А-Яа-я]+)\.?\s*([\s\S]*?)<\/b>\s*<\/p>/gi;

  const matches = [];
  let m;
  while ((m = headerRe.exec(text)) !== null) {
    matches.push({
      index: m.index,
      end: headerRe.lastIndex,
      number: (m[1] || '').trim(),
      title:  stripHtml(m[2] || '').trim(),
    });
  }

  const articles = [];
  for (let i = 0; i < matches.length; i++) {
    const cur = matches[i];
    const next = matches[i + 1];
    const bodyEnd = next ? next.index : text.length;
    const rawBody = text.slice(cur.end, bodyEnd);

    // Удаляем заголовки h3 (Глава/Параграф/Раздел) — они межблочные
    const cleanBody = rawBody.replace(/<h3[\s\S]*?<\/h3>/gi, '\n\n');
    const body = stripHtml(cleanBody);

    if (!cur.number) continue;
    if (body.length < 30) continue;

    articles.push({
      number: cur.number,
      title: cur.title,
      body,
    });
  }

  return articles;
}

// ── Чанкинг по пунктам статьи ────────────────────────────────────────────────
// В НК РК пункты обычно начинаются с "1.", "2." в начале строки, либо с подпунктов "1)".
// Каждый пункт логически самостоятелен — делаем по нему чанк, если статья длинная.

function chunkArticle(articleText) {
  if (articleText.length <= 1200) return [articleText];

  // Попытка разбить по пунктам
  const lines = articleText.split('\n');
  const chunks = [];
  let buf = '';
  for (const line of lines) {
    const isNewPoint = /^\s*(?:\d+\.\s|\d+\)\s)/.test(line);
    if (isNewPoint && buf.length > 400) {
      chunks.push(buf.trim());
      buf = line;
    } else {
      buf += (buf ? '\n' : '') + line;
    }
  }
  if (buf.trim()) chunks.push(buf.trim());

  // Если разбили на нечто слишком мелкое или вообще не разбили — fallback на стандартный чанкер
  if (chunks.length <= 1) return chunkText(articleText, 1200, 150);
  return chunks;
}

// ── Главная функция ингестии ─────────────────────────────────────────────────

async function ingestNkRk(opts = {}) {
  const url = opts.url || NK_RK_URL;
  console.log(`[ingest NK] fetching ${url}`);

  const html = url.includes('adilet.zan.kz')
    ? await fetchAdilet(url)
    : await (await fetch(url, {
        headers: {
          'User-Agent': 'Mozilla/5.0 EsepKZ/1.0 (knowledge indexer; +https://esep.kz)',
        },
      })).text();
  console.log(`[ingest NK] downloaded ${(html.length / 1024).toFixed(1)} KB`);

  const articles = parseArticles(html);
  console.log(`[ingest NK] parsed ${articles.length} articles`);

  if (articles.length === 0) {
    console.warn('[ingest NK] WARNING: 0 articles parsed. HTML structure may have changed.');
    return { articles: 0, indexed: 0, skipped: 0 };
  }

  let indexed = 0, skipped = 0;
  for (const a of articles) {
    const sourceUrl = `${url}#st-${a.number}`;
    const chunks = chunkArticle(a.body).map((text, i) => ({
      text: i === 0 ? `Статья ${a.number}. ${a.title}\n\n${text}` : text,
      audienceHint: 'all',
      complexity: 'expert', // НК — экспертный материал, в ответе должно быть упрощено LLM-ом
      anchor: `#st-${a.number}`,
    }));

    try {
      const result = await indexSource({
        url: sourceUrl,
        title: `НК РК ст. ${a.number}. ${a.title}`,
        sourceType: 'law',
        trustWeight: 1.0,
        publishedAt: '2025-07-18',
        rawContent: `Статья ${a.number}. ${a.title}\n\n${a.body}`,
        metadata: {
          law_code: 'NK_RK',
          law_doc_number: NK_RK_DOC_NUMBER,
          law_full_name: 'Кодекс Республики Казахстан "О налогах и других обязательных платежах в бюджет (Налоговый кодекс)"',
          law_act_number: '214-VIII',
          article: a.number,
          article_title: a.title,
        },
        chunks,
      });
      if (result.contentChanged) indexed++;
      else skipped++;
    } catch (err) {
      console.error(`[ingest NK] article ${a.number} failed:`, err.message);
    }
  }

  console.log(`[ingest NK] done: ${indexed} new/updated, ${skipped} unchanged`);
  return { articles: articles.length, indexed, skipped };
}

module.exports = { ingestNkRk, parseArticles, chunkArticle };

// CLI запуск: node src/jobs/ingestNkRk.js
if (require.main === module) {
  ingestNkRk()
    .then(r => { console.log('OK', r); process.exit(0); })
    .catch(e => { console.error(e); process.exit(1); });
}
