const express = require('express');
const https   = require('https');
const db      = require('../db');
const router  = express.Router();

// ═══════════════════════════════════════════════════════════════════════════════
// STAT.GOV.KZ — поиск компаний по названию / виду деятельности
// ═══════════════════════════════════════════════════════════════════════════════

function searchStatGov(query) {
  return new Promise((resolve, reject) => {
    const encoded = encodeURIComponent(query);
    const url = `https://old.stat.gov.kz/api/juridical/counter/api/?bin=&lang=ru&activity=&name=${encoded}`;

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
// GET /api/lpr/search?q=keyword&city=almaty
// Поиск компаний через stat.gov.kz по ключевому слову
// ═══════════════════════════════════════════════════════════════════════════════

router.get('/search', async (req, res) => {
  try {
    const { q, city } = req.query;

    if (!q || q.trim().length < 2) {
      return res.status(400).json({
        error: 'Параметр q должен содержать минимум 2 символа',
      });
    }

    let results = [];
    let source = 'stat.gov.kz';

    // Try stat.gov.kz first
    try {
      const raw = await searchStatGov(q.trim());
      // stat.gov.kz returns either an object or an array
      const items = Array.isArray(raw) ? raw : (raw?.obj ? [raw.obj] : []);
      results = items.map((item) => ({
        bin:          item.bin          || item.BIN      || null,
        companyName:  item.name         || item.NameRu   || null,
        directorName: item.fio          || item.HeadFio  || null,
        address:      item.address      || item.Address  || null,
        activity:     item.okedName     || item.Activity || null,
        city:         city              || null,
        source:       'stat.gov.kz',
      }));
    } catch (apiErr) {
      console.error('[lpr-search] stat.gov.kz error:', apiErr.message);
      source = 'database';
    }

    // If stat.gov.kz returned nothing or failed, search local DB
    if (results.length === 0) {
      source = 'database';
      let query = `
        SELECT id, bin, company_name, director_name, phone, email,
               source, city, activity, notes, created_at
        FROM lpr_contacts
        WHERE user_id = $1
          AND (company_name ILIKE $2 OR activity ILIKE $2 OR bin ILIKE $2)
      `;
      const params = [req.userId, `%${q.trim()}%`];

      if (city && city.trim().length > 0) {
        query += ` AND city ILIKE $3`;
        params.push(`%${city.trim()}%`);
      }

      query += ` ORDER BY created_at DESC LIMIT 50`;

      const { rows } = await db.query(query, params);
      results = rows.map((r) => ({
        id:           r.id,
        bin:          r.bin,
        companyName:  r.company_name,
        directorName: r.director_name,
        phone:        r.phone,
        email:        r.email,
        city:         r.city,
        activity:     r.activity,
        notes:        r.notes,
        source:       r.source || 'database',
        createdAt:    r.created_at,
      }));
    }

    // Filter by city if results came from stat.gov.kz and city was specified
    if (source === 'stat.gov.kz' && city && city.trim().length > 0) {
      const cityLower = city.trim().toLowerCase();
      results = results.filter((r) => {
        const addr = (r.address || '').toLowerCase();
        return addr.includes(cityLower);
      });
    }

    return res.json({
      source,
      count: results.length,
      results,
    });
  } catch (err) {
    console.error('[lpr-search] unexpected error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// POST /api/lpr/save — сохранить найденный контакт ЛПР
// ═══════════════════════════════════════════════════════════════════════════════

router.post('/save', async (req, res) => {
  try {
    const {
      bin, companyName, directorName,
      phone, email, source, city, activity, notes,
    } = req.body;

    if (!companyName || companyName.trim().length === 0) {
      return res.status(400).json({ error: 'Название компании обязательно' });
    }

    const { rows } = await db.query(`
      INSERT INTO lpr_contacts
        (user_id, bin, company_name, director_name, phone, email, source, city, activity, notes)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING id, bin, company_name, director_name, phone, email,
                source, city, activity, notes, created_at
    `, [
      req.userId,
      bin          || null,
      companyName.trim(),
      directorName || null,
      phone        || null,
      email        || null,
      source       || 'manual',
      city         || null,
      activity     || null,
      notes        || null,
    ]);

    const r = rows[0];
    return res.status(201).json({
      id:           r.id,
      bin:          r.bin,
      companyName:  r.company_name,
      directorName: r.director_name,
      phone:        r.phone,
      email:        r.email,
      source:       r.source,
      city:         r.city,
      activity:     r.activity,
      notes:        r.notes,
      createdAt:    r.created_at,
    });
  } catch (err) {
    console.error('[lpr-save] error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// GET /api/lpr/saved — все сохранённые контакты пользователя
// ═══════════════════════════════════════════════════════════════════════════════

router.get('/saved', async (req, res) => {
  try {
    const { rows } = await db.query(`
      SELECT id, bin, company_name, director_name, phone, email,
             source, city, activity, notes, created_at
      FROM lpr_contacts
      WHERE user_id = $1
      ORDER BY created_at DESC
    `, [req.userId]);

    const contacts = rows.map((r) => ({
      id:           r.id,
      bin:          r.bin,
      companyName:  r.company_name,
      directorName: r.director_name,
      phone:        r.phone,
      email:        r.email,
      source:       r.source,
      city:         r.city,
      activity:     r.activity,
      notes:        r.notes,
      createdAt:    r.created_at,
    }));

    return res.json({ count: contacts.length, contacts });
  } catch (err) {
    console.error('[lpr-saved] error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// DELETE /api/lpr/:id — удалить сохранённый контакт
// ═══════════════════════════════════════════════════════════════════════════════

router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const { rowCount } = await db.query(`
      DELETE FROM lpr_contacts
      WHERE id = $1 AND user_id = $2
    `, [id, req.userId]);

    if (rowCount === 0) {
      return res.status(404).json({ error: 'Контакт не найден' });
    }

    return res.json({ ok: true });
  } catch (err) {
    console.error('[lpr-delete] error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

module.exports = router;
