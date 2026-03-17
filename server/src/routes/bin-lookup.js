const express = require('express');
const https   = require('https');
const router  = express.Router();

// ═══════════════════════════════════════════════════════════════════════════════
// IN-MEMORY CACHE — TTL 1 hour
// ═══════════════════════════════════════════════════════════════════════════════

const cache    = new Map();
const CACHE_TTL = 60 * 60 * 1000; // 1 hour

function getCached(bin) {
  const entry = cache.get(bin);
  if (!entry) return null;
  if (Date.now() - entry.ts > CACHE_TTL) {
    cache.delete(bin);
    return null;
  }
  return entry.data;
}

function setCache(bin, data) {
  cache.set(bin, { data, ts: Date.now() });
}

// ═══════════════════════════════════════════════════════════════════════════════
// BIN STRUCTURE HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Digits 5-6 of BIN encode entity type.
 * Common codes per Казахстанский стандарт БИН:
 *   4x — юридическое лицо (ТОО, ПК, etc.)
 *   5x — акционерное общество (АО)
 *   6x — филиал / представительство
 *   3x — ИП (индивидуальный предприниматель)
 */
const ENTITY_TYPES = {
  '40': 'ТОО (товарищество с ограниченной ответственностью)',
  '41': 'ТОО (полное товарищество)',
  '42': 'ТОО (коммандитное товарищество)',
  '43': 'ТОО (товарищество с дополнительной ответственностью)',
  '44': 'Производственный кооператив',
  '45': 'Потребительский кооператив',
  '46': 'Религиозное объединение',
  '47': 'Фонд',
  '48': 'Объединение юридических лиц',
  '49': 'Учреждение',
  '50': 'АО (акционерное общество)',
  '51': 'Государственное предприятие',
  '52': 'Государственное учреждение',
  '60': 'Филиал',
  '61': 'Представительство',
  '30': 'ИП (индивидуальный предприниматель)',
  '31': 'ИП (совместное предпринимательство)',
  '32': 'КХ (крестьянское хозяйство)',
  '33': 'ФХ (фермерское хозяйство)',
};

function parseEntityType(bin) {
  const code = bin.substring(4, 6);
  return {
    code,
    name: ENTITY_TYPES[code] || `Неизвестный тип (${code})`,
    isIP: code.startsWith('3'),
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAT.GOV.KZ FETCH — uses built-in https (same pattern as telegram.js)
// ═══════════════════════════════════════════════════════════════════════════════

function fetchFromStatGov(bin) {
  return new Promise((resolve, reject) => {
    const url = `https://old.stat.gov.kz/api/juridical/counter/api/?bin=${bin}&lang=ru`;

    const req = https.get(url, { timeout: 10000 }, (res) => {
      if (res.statusCode !== 200) {
        return reject(new Error(`stat.gov.kz returned ${res.statusCode}`));
      }

      let buf = '';
      res.on('data', (chunk) => buf += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(buf);
          resolve(json);
        } catch {
          reject(new Error('Не удалось разобрать ответ stat.gov.kz'));
        }
      });
    });

    req.on('error', (err) => reject(err));
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Таймаут запроса к stat.gov.kz'));
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// NORMALIZE — приводим ответ stat.gov.kz к единому формату
// ═══════════════════════════════════════════════════════════════════════════════

function normalizeResponse(bin, raw) {
  const obj = raw?.obj || raw;
  const entity = parseEntityType(bin);

  return {
    bin,
    name:             obj?.name            || obj?.NameRu  || null,
    director:         obj?.fio             || obj?.HeadFio || null,
    address:          obj?.address         || obj?.Address || null,
    registrationDate: obj?.registrationDate || obj?.RegDate || null,
    activityCode:     obj?.okedCode        || obj?.KATOCode || null,
    activityName:     obj?.okedName        || obj?.Activity || null,
    entityType:       entity.name,
    isIP:             entity.isIP,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// GET /api/bin/:bin
// ═══════════════════════════════════════════════════════════════════════════════

router.get('/:bin', async (req, res) => {
  try {
    const { bin } = req.params;

    // ── Validation ──────────────────────────────────────────────────────────
    if (!/^\d{12}$/.test(bin)) {
      return res.status(400).json({
        error: 'БИН должен содержать ровно 12 цифр',
      });
    }

    // ── Cache check ─────────────────────────────────────────────────────────
    const cached = getCached(bin);
    if (cached) {
      return res.json(cached);
    }

    // ── Fetch from stat.gov.kz ──────────────────────────────────────────────
    try {
      const raw = await fetchFromStatGov(bin);
      const data = normalizeResponse(bin, raw);
      setCache(bin, data);
      return res.json(data);
    } catch (apiErr) {
      console.error(`[bin-lookup] stat.gov.kz error for ${bin}:`, apiErr.message);

      // Fallback: return what we can parse from the BIN structure itself
      const entity = parseEntityType(bin);
      return res.status(502).json({
        bin,
        name:             null,
        director:         null,
        address:          null,
        registrationDate: null,
        activityCode:     null,
        activityName:     null,
        entityType:       entity.name,
        isIP:             entity.isIP,
        warning:          'Не удалось получить данные с stat.gov.kz. ' +
                          'Проверьте БИН вручную: https://pk.uchet.kz/company/search/ ' +
                          'или https://egov.kz',
        apiError:         apiErr.message,
      });
    }
  } catch (err) {
    console.error('[bin-lookup] unexpected error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

module.exports = router;
