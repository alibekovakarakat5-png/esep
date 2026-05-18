/**
 * Универсальный поиск налогоплательщика по БИН/ИИН — с каскадом источников.
 *
 * Порядок попыток:
 *   1) stat.gov.kz (основной, бесплатный, JSON)
 *   2) Параграф ba.prg.kz (если есть ключ — TODO)
 *   3) Fallback на parseEntityType — хотя бы тип компании из структуры БИН
 *
 * Каждый источник — с своим таймаутом, User-Agent, обработкой ошибок.
 * Возвращаем единый нормализованный формат.
 */

const https = require('https');

// Те же коды, что в routes/bin-lookup.js — единый источник правды
const ENTITY_TYPES = {
  '40': { name: 'ТОО', kind: 'too' },
  '41': { name: 'ТОО (полное товарищество)', kind: 'too' },
  '42': { name: 'ТОО (коммандитное товарищество)', kind: 'too' },
  '43': { name: 'ТОО (с дополнительной ответственностью)', kind: 'too' },
  '44': { name: 'Производственный кооператив', kind: 'cooperative' },
  '45': { name: 'Потребительский кооператив', kind: 'cooperative' },
  '46': { name: 'Религиозное объединение', kind: 'organization' },
  '47': { name: 'Фонд', kind: 'organization' },
  '48': { name: 'Объединение юридических лиц', kind: 'organization' },
  '49': { name: 'Учреждение', kind: 'organization' },
  '50': { name: 'АО', kind: 'ao' },
  '51': { name: 'Государственное предприятие', kind: 'state' },
  '52': { name: 'Государственное учреждение', kind: 'state' },
  '60': { name: 'Филиал', kind: 'branch' },
  '61': { name: 'Представительство', kind: 'branch' },
  '30': { name: 'ИП', kind: 'ip' },
  '31': { name: 'ИП (совместное предпринимательство)', kind: 'ip' },
  '32': { name: 'КХ (крестьянское хозяйство)', kind: 'farming' },
  '33': { name: 'ФХ (фермерское хозяйство)', kind: 'farming' },
};

function parseEntityType(bin) {
  const code = bin.substring(4, 6);
  if (ENTITY_TYPES[code]) {
    return {
      code,
      ...ENTITY_TYPES[code],
      is_ip: ENTITY_TYPES[code].kind === 'ip',
    };
  }
  return { code, name: 'Физическое лицо', kind: 'individual', is_ip: false };
}

/**
 * Источник 1: stat.gov.kz публичный JSON API.
 * Может вернуть 403, если IP в блок-листе.
 */
function tryStatGovKz(bin) {
  return new Promise((resolve) => {
    const url = `https://old.stat.gov.kz/api/juridical/counter/api/?bin=${bin}&lang=ru`;

    const req = https.get(url, {
      timeout: 8000,
      headers: {
        // Маскируемся под обычный браузер — иногда помогает обойти block
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
                      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'ru-RU,ru;q=0.9',
        'Referer': 'https://stat.gov.kz/',
      },
    }, (res) => {
      if (res.statusCode !== 200) {
        return resolve({ ok: false, source: 'stat.gov.kz', error: `HTTP ${res.statusCode}` });
      }
      let buf = '';
      res.on('data', (c) => (buf += c));
      res.on('end', () => {
        try {
          const json = JSON.parse(buf);
          const obj = json?.obj || json;
          if (!obj || (!obj.name && !obj.NameRu && !obj.okedCode)) {
            return resolve({ ok: false, source: 'stat.gov.kz', error: 'empty response' });
          }
          resolve({
            ok: true,
            source: 'stat.gov.kz',
            data: {
              name: obj.name || obj.NameRu || null,
              director: obj.fio || obj.HeadFio || null,
              address: obj.address || obj.Address || null,
              registration_date: obj.registrationDate || obj.RegDate || null,
              oked_code: obj.okedCode || null,
              oked_name: obj.okedName || null,
              secondary_okeds: obj.secondOkeds || [],
              krp_code: obj.krpCode || null,
              krp_name: obj.krpName || null,
              kato_code: obj.katoCode || null,
              kato_address: obj.katoAddress || null,
            },
          });
        } catch (e) {
          resolve({ ok: false, source: 'stat.gov.kz', error: 'parse error: ' + e.message });
        }
      });
    });

    req.on('error', (err) => {
      resolve({ ok: false, source: 'stat.gov.kz', error: err.message });
    });
    req.on('timeout', () => {
      req.destroy();
      resolve({ ok: false, source: 'stat.gov.kz', error: 'timeout' });
    });
  });
}

/**
 * Главная функция — каскад источников.
 *
 * @param {string} bin - 12 цифр
 * @returns {Promise<{found: bool, source: string, data: object, errors: string[]}>}
 */
async function lookupTaxpayer(bin) {
  const errors = [];

  // ── Попытка 1: stat.gov.kz ─────────────────────────────────────────────
  const r1 = await tryStatGovKz(bin);
  if (r1.ok) {
    const entity = parseEntityType(bin);
    return {
      found: true,
      source: r1.source,
      data: {
        bin,
        entity_type: entity,
        ...r1.data,
      },
      errors,
    };
  }
  errors.push(`${r1.source}: ${r1.error}`);

  // ── Попытка 2: Параграф ba.prg.kz (TODO — нужен договор) ──────────────
  // const r2 = await tryParagraph(bin);
  // if (r2.ok) { ... }

  // ── Fallback: только структура БИН ─────────────────────────────────────
  const entity = parseEntityType(bin);
  return {
    found: false,
    source: 'fallback (BIN structure only)',
    data: {
      bin,
      entity_type: entity,
      name: null,
      director: null,
      address: null,
      oked_code: null,
      oked_name: null,
    },
    errors,
    note: 'Внешние реестры недоступны. Возвращены только данные, выводимые из самой структуры БИН.',
  };
}

module.exports = { lookupTaxpayer, parseEntityType, ENTITY_TYPES };
