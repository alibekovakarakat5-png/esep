/**
 * Platform Service #2 + #3: Проверка СНР/ОКЭД + Статус ИП/ФЛ/ТОО
 *
 * Источник данных: stat.gov.kz публичный API (через services/bin_via_stat_gov.js)
 *
 * Покрывает:
 *   - Сервис 2: ОКЭД, доп. ОКЭДы, СНР (выводится из okedCode + структуры компании)
 *   - Сервис 3: статус (ИП / ТОО / АО / филиал / самозанятый)
 *
 * Endpoint:
 *   GET /api/platform/taxpayer/:bin
 *   Авторизация: X-Platform-Key
 */

const express = require('express');
const https = require('https');
const router = express.Router();
const { requirePlatformKey } = require('../../middleware/platform_api_key');
const { validateIinChecksum } = require('../../services/iin_algorithm');

// Кэш на 1 час (как в bin-lookup.js)
const cache = new Map();
const CACHE_TTL = 60 * 60 * 1000;

function getCached(bin) {
  const e = cache.get(bin);
  if (!e) return null;
  if (Date.now() - e.ts > CACHE_TTL) {
    cache.delete(bin);
    return null;
  }
  return e.data;
}

function setCache(bin, data) {
  cache.set(bin, { data, ts: Date.now() });
}

// Те же коды что в routes/bin-lookup.js — единый источник правды
const ENTITY_TYPES = {
  '40': { name: 'ТОО (товарищество с ограниченной ответственностью)', kind: 'too' },
  '41': { name: 'ТОО (полное товарищество)', kind: 'too' },
  '42': { name: 'ТОО (коммандитное товарищество)', kind: 'too' },
  '43': { name: 'ТОО (с дополнительной ответственностью)', kind: 'too' },
  '44': { name: 'Производственный кооператив', kind: 'cooperative' },
  '45': { name: 'Потребительский кооператив', kind: 'cooperative' },
  '46': { name: 'Религиозное объединение', kind: 'organization' },
  '47': { name: 'Фонд', kind: 'organization' },
  '48': { name: 'Объединение юридических лиц', kind: 'organization' },
  '49': { name: 'Учреждение', kind: 'organization' },
  '50': { name: 'АО (акционерное общество)', kind: 'ao' },
  '51': { name: 'Государственное предприятие', kind: 'state' },
  '52': { name: 'Государственное учреждение', kind: 'state' },
  '60': { name: 'Филиал', kind: 'branch' },
  '61': { name: 'Представительство', kind: 'branch' },
  '30': { name: 'ИП (индивидуальный предприниматель)', kind: 'ip' },
  '31': { name: 'ИП (совместное предпринимательство)', kind: 'ip' },
  '32': { name: 'КХ (крестьянское хозяйство)', kind: 'farming' },
  '33': { name: 'ФХ (фермерское хозяйство)', kind: 'farming' },
};

function parseEntityType(bin) {
  // У ИИН физлица позиция 5-6 имеет другой смысл, поэтому возвращаем 'individual'
  // если 5-6 не подходят ни под один код БИН.
  const code = bin.substring(4, 6);
  if (ENTITY_TYPES[code]) {
    return {
      code,
      ...ENTITY_TYPES[code],
      isIP: ENTITY_TYPES[code].kind === 'ip',
    };
  }
  return { code, name: 'Физическое лицо (по структуре ИИН)', kind: 'individual', isIP: false };
}

function fetchFromStatGov(bin) {
  return new Promise((resolve, reject) => {
    const url = `https://old.stat.gov.kz/api/juridical/counter/api/?bin=${bin}&lang=ru`;
    const req = https.get(url, { timeout: 10000 }, (res) => {
      if (res.statusCode !== 200) {
        return reject(new Error(`stat.gov.kz returned ${res.statusCode}`));
      }
      let buf = '';
      res.on('data', (c) => (buf += c));
      res.on('end', () => {
        try {
          resolve(JSON.parse(buf));
        } catch {
          reject(new Error('Не удалось разобрать ответ stat.gov.kz'));
        }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Таймаут запроса к stat.gov.kz'));
    });
  });
}

/**
 * Источник 2: КГД ИСНА (официальный реестр).
 *
 * Работает по токену X-Portal-Token, выданному КГД. Из доступных нам методов
 * данные отдаёт только /open-api/global/find-risk-degree: официальное
 * наименование + степень риска налогоплательщика.
 *
 * СНР и ОКЭД этот метод НЕ возвращает — они закрыты reCAPTCHA
 * (см. письмо в КГД: Esep-pismo-kgd-isna.pdf).
 */
function fetchFromKgd(code) {
  return new Promise((resolve, reject) => {
    const token = process.env.KGD_API_TOKEN;
    const base = process.env.KGD_ISNA_BASE_URL || 'https://knp.kgd.gov.kz';
    if (!token) return reject(new Error('KGD_API_TOKEN не задан'));

    const url = `${base}/services/isnaportalsync/open-api/global/find-risk-degree`
      + `?taxpayerCode=${encodeURIComponent(code)}`;

    const req = https.get(url, { timeout: 10000, headers: { 'X-Portal-Token': token } }, (res) => {
      if (res.statusCode !== 200) {
        return reject(new Error(`КГД ответил ${res.statusCode}`));
      }
      let buf = '';
      res.on('data', (c) => (buf += c));
      res.on('end', () => {
        try {
          const json = JSON.parse(buf);
          // КГД отдаёт 200 с errorResponse, если запрос не отработал
          if (json?.errorResponse || !json?.name) {
            return reject(new Error(json?.errorResponse?.errorMessage || 'нет данных в реестре КГД'));
          }
          resolve(json);
        } catch {
          reject(new Error('Не удалось разобрать ответ КГД'));
        }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Таймаут запроса к КГД')); });
  });
}

function normalize(bin, raw, kgd = null) {
  const obj = raw?.obj || raw;
  const entity = parseEntityType(bin);

  return {
    bin,
    found_in_registry: Boolean(obj?.name || obj?.NameRu || kgd?.name),
    entity_type: {
      code: entity.code,
      name: entity.name,
      kind: entity.kind,
      is_ip: entity.isIP,
      is_individual: entity.kind === 'individual',
    },
    // Наименование от КГД приоритетнее — это официальный реестр
    name: kgd?.name || obj?.name || obj?.NameRu || null,
    director: obj?.fio || obj?.HeadFio || null,
    address: obj?.address || obj?.Address || null,
    registration_date: obj?.registrationDate || obj?.RegDate || null,
    oked: {
      main_code: obj?.okedCode || null,
      main_name: obj?.okedName || null,
      secondary: obj?.secondOkeds || [],
    },
    krp: {
      code: obj?.krpCode || null,
      name: obj?.krpName || null,
    },
    location: {
      kato_code: obj?.katoCode || null,
      address: obj?.katoAddress || null,
    },
    // Степень риска — только у КГД, в stat.gov.kz такого нет
    risk_degree: kgd ? {
      degree: kgd.degree || null,
      relevance_date: kgd.relevanceDate || null,
      begin_date: kgd.beginDate || null,
      end_date: kgd.endDate || null,
    } : null,
    sources: [kgd ? 'КГД ИСНА' : null, obj?.name || obj?.NameRu ? 'stat.gov.kz' : null].filter(Boolean),
    source: kgd ? 'КГД ИСНА' : 'stat.gov.kz',
    fetched_at: new Date().toISOString(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/platform/taxpayer/:bin
// ─────────────────────────────────────────────────────────────────────────────
router.get(
  '/:bin',
  requirePlatformKey('taxpayer_info'),
  async (req, res) => {
    const { bin } = req.params;

    if (!/^\d{12}$/.test(bin)) {
      return res.status(400).json({
        error: 'БИН/ИИН должен содержать ровно 12 цифр',
      });
    }

    // Если это ИИН — дополнительно проверим контрольную цифру
    // (для БИН ТОО — тоже 12 цифр, но без алгоритма ИИН)
    const probableIin = bin.substring(4, 6).startsWith('3') === false
      && bin.substring(4, 6).startsWith('4') === false
      && bin.substring(4, 6).startsWith('5') === false
      && bin.substring(4, 6).startsWith('6') === false;

    if (probableIin) {
      const iinCheck = validateIinChecksum(bin);
      if (!iinCheck.valid) {
        return res.status(400).json({
          error: 'Похоже на ИИН, но контрольная цифра не сходится',
          reason: iinCheck.reason,
        });
      }
    }

    // ── Кэш ────────────────────────────────────────────────────────────────
    const cached = getCached(bin);
    if (cached) {
      return res.json({ ...cached, cache_hit: true });
    }

    // Спрашиваем оба источника разом: КГД даёт официальное наименование и
    // степень риска, stat.gov.kz — ОКЭД, адрес, руководителя. Падение одного
    // не должно ронять ответ.
    const [kgdRes, statRes] = await Promise.allSettled([
      fetchFromKgd(bin),
      fetchFromStatGov(bin),
    ]);

    const kgd = kgdRes.status === 'fulfilled' ? kgdRes.value : null;
    const stat = statRes.status === 'fulfilled' ? statRes.value : null;
    const errors = [];
    if (kgdRes.status === 'rejected') errors.push(`КГД: ${kgdRes.reason.message}`);
    if (statRes.status === 'rejected') errors.push(`stat.gov.kz: ${statRes.reason.message}`);

    if (kgd || stat) {
      const data = normalize(bin, stat, kgd);
      // Часть источников могла отвалиться — говорим об этом прямо, но ответ отдаём
      if (errors.length) data.partial_errors = errors;
      setCache(bin, data);
      return res.json({ ...data, cache_hit: false });
    }

    console.error(`[taxpayer] все источники недоступны для ${bin}: ${errors.join('; ')}`);
    const entity = parseEntityType(bin);
    return res.status(502).json({
      bin,
      found_in_registry: false,
      entity_type: {
        code: entity.code,
        name: entity.name,
        kind: entity.kind,
        is_ip: entity.isIP,
      },
      warning: 'Реестры недоступны, возвращены только данные из структуры БИН/ИИН',
      api_error: errors.join('; '),
      source: 'fallback',
    });
  },
);

module.exports = router;
