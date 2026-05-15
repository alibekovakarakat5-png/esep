const router = require('express').Router();
const db     = require('../db');
const { TIERS, normalizeTier } = require('../tiers');

// BUG 7: XSS prevention helper
function escapeHtml(str) {
  if (str == null) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ── Simple password middleware ────────────────────────────────────────────────
function getCookie(req, name) {
  const raw = req.headers.cookie ?? '';
  const parts = raw.split(';').map(p => p.trim());
  const found = parts.find(p => p.startsWith(`${name}=`));
  return found ? decodeURIComponent(found.slice(name.length + 1)) : '';
}

function adminAuth(req, res, next) {
  const pass = process.env.ADMIN_PASSWORD;
  if (!pass) return res.status(500).send('ADMIN_PASSWORD not set');

  const auth = req.headers['authorization'] ?? '';
  // Basic auth: Authorization: Bearer <password>
  if (auth === `Bearer ${pass}`) return next();

  if (getCookie(req, 'esep_admin') === pass) return next();

  const wantsHtmlPage = req.method === 'GET' &&
    (req.headers.accept ?? '').includes('text/html');
  if (wantsHtmlPage) return res.redirect('/api/admin/login');

  res.status(401).json({ error: 'Unauthorized' });
}

router.get('/login', (_req, res) => {
  res.send(`<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Esep Admin Login</title>
  <style>
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f8faff;color:#1a1a2e;min-height:100vh;display:grid;place-items:center;margin:0}
    form{width:min(360px,calc(100vw - 32px));background:#fff;border:1px solid #e5e7eb;border-radius:16px;padding:24px;box-shadow:0 10px 30px rgba(15,23,42,.08)}
    h1{font-size:22px;margin:0 0 6px}
    p{font-size:13px;color:#6b7280;margin:0 0 18px}
    input{width:100%;padding:12px;border:1px solid #d1d5db;border-radius:10px;font-size:15px;box-sizing:border-box}
    button{width:100%;margin-top:14px;padding:12px;border:0;border-radius:10px;background:#2563eb;color:#fff;font-weight:700;cursor:pointer}
    .err{display:none;margin-top:10px;color:#dc2626;font-size:13px}
  </style>
</head>
<body>
  <form id="login-form">
    <h1>Esep Admin</h1>
    <p>Введите ADMIN_PASSWORD для ручной активации тарифов.</p>
    <input id="pass" type="password" placeholder="Пароль" autocomplete="current-password" autofocus>
    <button type="submit">Войти</button>
    <div id="err" class="err">Неверный пароль</div>
  </form>
  <script>
    document.getElementById('login-form').addEventListener('submit', async (e) => {
      e.preventDefault();
      const r = await fetch('/api/admin/login', {
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({pass:document.getElementById('pass').value})
      });
      if (r.ok) location.href = '/api/admin';
      else document.getElementById('err').style.display = 'block';
    });
  </script>
</body>
</html>`);
});

router.post('/login', (req, res) => {
  const pass = process.env.ADMIN_PASSWORD;
  if (!pass) return res.status(500).json({ error: 'ADMIN_PASSWORD not set' });
  if (req.body?.pass !== pass) return res.status(401).json({ error: 'Unauthorized' });
  const secure = process.env.NODE_ENV === 'production' ? '; Secure' : '';
  res.setHeader('Set-Cookie', `esep_admin=${encodeURIComponent(pass)}; HttpOnly; SameSite=Lax; Path=/api; Max-Age=86400${secure}`);
  res.json({ ok: true });
});

// ── GET /api/admin/users ──────────────────────────────────────────────────────
router.get('/users', adminAuth, async (req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT id, email, name, tier, is_beta_tester, created_at,
              (SELECT COUNT(*) FROM transactions WHERE user_id = users.id) AS tx_total,
              (SELECT COUNT(*) FROM invoices   WHERE user_id = users.id) AS inv_total
       FROM users
       ORDER BY created_at DESC`,
    );
    res.json(rows);
  } catch (err) {
    console.error('GET /admin/users error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── PATCH /api/admin/users/:id/beta-tester ───────────────────────────────────
// Body: { is: true | false }
// Toggles the "Сообщить о баге" button visibility for that user.
router.patch('/users/:id/beta-tester', adminAuth, async (req, res) => {
  try {
    const is = !!req.body?.is;
    await db.query('UPDATE users SET is_beta_tester = $1 WHERE id = $2', [is, req.params.id]);
    res.json({ ok: true, isBetaTester: is });
  } catch (err) {
    console.error('PATCH /admin/users/:id/beta-tester error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── GET /api/admin/feedback ──────────────────────────────────────────────────
// Return recent feedback entries from beta testers, newest first.
router.get('/feedback', adminAuth, async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit, 10) || 100, 500);
    const { rows } = await db.query(
      `SELECT f.id, f.user_id, u.email, u.name, f.screen, f.severity, f.message,
              f.device_info, f.app_version, f.status, f.created_at
       FROM feedback f
       JOIN users u ON u.id = f.user_id
       ORDER BY f.created_at DESC
       LIMIT $1`,
      [limit],
    );
    res.json(rows);
  } catch (err) {
    console.error('GET /admin/feedback error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── PATCH /api/admin/feedback/:id/status ─────────────────────────────────────
router.patch('/feedback/:id/status', adminAuth, async (req, res) => {
  try {
    const status = String(req.body?.status || '').trim();
    const ALLOWED = ['new', 'in_progress', 'fixed', 'wontfix', 'duplicate'];
    if (!ALLOWED.includes(status)) {
      return res.status(400).json({ error: `status must be one of: ${ALLOWED.join(', ')}` });
    }
    await db.query('UPDATE feedback SET status = $1 WHERE id = $2', [status, req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    console.error('PATCH /admin/feedback/:id/status error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── PATCH /api/admin/users/:id/tier ──────────────────────────────────────────
router.patch('/users/:id/tier', adminAuth, async (req, res) => {
  try {
    const tier = normalizeTier(req.body?.tier);
    if (!TIERS.includes(tier)) {
      return res.status(400).json({ error: `tier must be one of: ${TIERS.join(', ')}` });
    }
    await db.query('UPDATE users SET tier = $1 WHERE id = $2', [tier, req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    console.error('PATCH /admin/users/:id/tier error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── POST /api/admin/payments — create payment & activate tier ────────────────
router.post('/payments', adminAuth, async (req, res) => {
  try {
    const { user_id, period, amount, payment_method, kaspi_txn_id, note } = req.body ?? {};
    const tier = normalizeTier(req.body?.tier);
    if (!user_id || !tier || !amount) {
      return res.status(400).json({ error: 'user_id, tier, amount required' });
    }
    if (!TIERS.includes(tier)) {
      return res.status(400).json({ error: `tier must be one of: ${TIERS.join(', ')}` });
    }

    // Calculate expiration
    const months = { monthly: 1, quarterly: 3, yearly: 12 }[period] ?? 1;
    const expiresAt = new Date();
    expiresAt.setMonth(expiresAt.getMonth() + months);

    const client = await db.connect();
    try {
      await client.query('BEGIN');

      // Create payment record
      const { rows } = await client.query(
        `INSERT INTO payments (user_id, tier, period, amount, status, payment_method, kaspi_txn_id, expires_at, paid_at, note)
         VALUES ($1, $2, $3, $4, 'paid', $5, $6, $7, NOW(), $8)
         RETURNING *`,
        [user_id, tier, period ?? 'monthly', amount, payment_method ?? 'kaspi_pay', kaspi_txn_id ?? null, expiresAt, note ?? null],
      );

      // Upgrade user tier
      await client.query(
        `UPDATE users
            SET tier = $1,
                subscription_expires_at = $2
          WHERE id = $3`,
        [tier, expiresAt, user_id],
      );

      await client.query('COMMIT');
      res.status(201).json(rows[0]);
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  } catch (err) {
    console.error('POST /admin/payments error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── GET /api/admin/payments ─────────────────────────────────────────────────
router.get('/payments', adminAuth, async (_req, res) => {
  try {
    const { rows } = await db.query(`
      SELECT p.*, u.email, u.name
        FROM payments p
        JOIN users u ON u.id = p.user_id
       ORDER BY p.created_at DESC
       LIMIT 200
    `);
    res.json(rows);
  } catch (err) {
    console.error('GET /admin/payments error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── PATCH /api/admin/payments/:id/expire — manually expire ──────────────────
router.patch('/payments/:id/expire', adminAuth, async (req, res) => {
  try {
    const { rows } = await db.query(
      `UPDATE payments SET status = 'expired' WHERE id = $1 RETURNING user_id`,
      [req.params.id],
    );
    if (rows.length > 0) {
      // Check if user has other active payments
      const { rows: other } = await db.query(
        `SELECT 1 FROM payments
          WHERE user_id = $1
            AND status = 'paid'
            AND id != $2
            AND expires_at > NOW()
          LIMIT 1`,
        [rows[0].user_id, req.params.id],
      );
      const { rows: promos } = await db.query(
        `SELECT 1 FROM promo_usages WHERE user_id = $1 AND expires_at > NOW() LIMIT 1`,
        [rows[0].user_id],
      );
      if (other.length === 0 && promos.length === 0) {
        await db.query(
          'UPDATE users SET tier = $1, subscription_expires_at = NULL WHERE id = $2',
          ['free', rows[0].user_id],
        );
      }
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('PATCH /admin/payments/:id/expire error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── PATCH /api/admin/payments/:id/extend — extend by N months ───────────────
router.patch('/payments/:id/extend', adminAuth, async (req, res) => {
  try {
    const months = parseInt(req.body?.months) || 1;
    const { rows } = await db.query(
      `UPDATE payments
         SET expires_at = GREATEST(expires_at, NOW()) + ($1 || ' months')::INTERVAL,
             status = 'paid'
       WHERE id = $2
       RETURNING user_id, tier, expires_at`,
      [months, req.params.id],
    );
    if (rows.length > 0) {
      await db.query(
        `UPDATE users SET tier = $1, subscription_expires_at = $2 WHERE id = $3`,
        [normalizeTier(rows[0].tier), rows[0].expires_at, rows[0].user_id],
      );
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('PATCH /admin/payments/:id/extend error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── GET /api/admin — HTML dashboard ──────────────────────────────────────────
router.get('/', adminAuth, async (_req, res) => {
  try {
    const [{ rows: users }, { rows: taxRows }, { rows: arts }, { rows: feedback }] = await Promise.all([
      db.query(
        `SELECT id, email, name, tier, is_beta_tester, created_at,
                (SELECT COUNT(*) FROM transactions WHERE user_id = users.id) AS tx_total,
                (SELECT COUNT(*) FROM invoices   WHERE user_id = users.id) AS inv_total
         FROM users ORDER BY created_at DESC`,
      ),
      db.query('SELECT key, value, label, updated_at FROM tax_config ORDER BY id'),
      db.query(
        `SELECT id, slug, title, audience, status, tags, published_at, created_at
         FROM articles ORDER BY created_at DESC LIMIT 50`,
      ),
      db.query(
        `SELECT f.id, f.user_id, u.email, u.name, f.screen, f.severity, f.message,
                f.device_info, f.app_version, f.status, f.created_at
           FROM feedback f
           JOIN users u ON u.id = f.user_id
          ORDER BY f.created_at DESC
          LIMIT 200`,
      ),
    ]);

    const promoData = await db.query(
      `SELECT p.*, (SELECT COUNT(*) FROM promo_usages WHERE promo_id = p.id) AS actual_uses
       FROM promo_codes p ORDER BY p.created_at DESC`
    );
    const promos = promoData.rows;

    // Payments with user info
    const paymentData = await db.query(`
      SELECT p.*, u.email AS user_email, u.name AS user_name
        FROM payments p
        JOIN users u ON u.id = p.user_id
       ORDER BY p.created_at DESC
       LIMIT 100
    `);
    const payments = paymentData.rows;

    const tierColor = { free: '#6b7280', solo: '#2563eb', accountant: '#7c3aed', accountant_pro: '#d97706' };

    // Pre-compute promos HTML
    const promoRows = promos.map((p) => {
      return `
      <tr>
        <td style="font-family:monospace;font-weight:700;letter-spacing:2px">${escapeHtml(p.code)}</td>
        <td><span class="badge" style="background:${tierColor[p.grant_tier] ?? '#6b7280'}20;color:${tierColor[p.grant_tier] ?? '#6b7280'}">${escapeHtml(p.grant_tier)}</span></td>
        <td>${p.duration_days}</td>
        <td>${p.actual_uses}</td>
        <td>${p.max_uses === 0 ? '&infin;' : p.max_uses}</td>
        <td><span class="badge" style="background:${p.active ? '#dcfce7' : '#fee2e2'};color:${p.active ? '#16a34a' : '#dc2626'}">${p.active ? 'Активен' : 'Выключен'}</span></td>
        <td><button onclick="deletePromo(${p.id})" style="padding:3px 8px;border:none;background:#fee2e2;color:#dc2626;border-radius:5px;cursor:pointer;font-size:12px">Выключить</button></td>
      </tr>`;
    }).join('');

    // Pre-compute payments HTML
    const now = Date.now();
    const paymentRows = payments.map((p) => {
      const exp = p.expires_at ? new Date(p.expires_at).getTime() : null;
      const isExpiring = p.status === 'paid' && exp && exp < now + 3 * 86400000 && exp > now;
      const isExpired = p.status === 'expired';
      const statusColor = isExpired ? '#dc2626' : isExpiring ? '#b45309' : p.status === 'paid' ? '#16a34a' : '#6b7280';
      const statusBg = isExpired ? '#fee2e2' : isExpiring ? '#fef3c7' : p.status === 'paid' ? '#dcfce7' : '#f3f4f6';
      const statusLabel = isExpired ? 'Истёк' : isExpiring ? 'Скоро истекает' : p.status === 'paid' ? 'Активен' : escapeHtml(p.status);
      const daysLeft = exp ? Math.ceil((exp - now) / 86400000) : null;
      const daysStr = daysLeft !== null && p.status === 'paid' ? ' (' + daysLeft + ' дн.)' : '';
      const paidDate = p.paid_at ? new Date(p.paid_at).toLocaleDateString('ru-RU') : '&mdash;';
      const expDate = p.expires_at ? new Date(p.expires_at).toLocaleDateString('ru-RU') : '&mdash;';
      const safeId = escapeHtml(p.id);

      let actions = '';
      if (p.status === 'paid') {
        actions = `<button onclick="extendPayment('${safeId}')" style="padding:3px 8px;border:none;background:#dcfce7;color:#16a34a;border-radius:5px;cursor:pointer;font-size:12px">+1 мес</button>
          <button onclick="expirePayment('${safeId}')" style="padding:3px 8px;border:none;background:#fee2e2;color:#dc2626;border-radius:5px;cursor:pointer;font-size:12px;margin-left:4px">Закрыть</button>`;
      } else {
        actions = `<button onclick="extendPayment('${safeId}')" style="padding:3px 8px;border:none;background:#dcfce7;color:#16a34a;border-radius:5px;cursor:pointer;font-size:12px">Возобновить</button>`;
      }

      return `
      <tr>
        <td>${escapeHtml(p.user_email)}</td>
        <td><span class="badge" style="background:${tierColor[p.tier] ?? '#6b7280'}20;color:${tierColor[p.tier] ?? '#6b7280'}">${escapeHtml(p.tier)}</span></td>
        <td>${p.amount} &#8376;</td>
        <td>${escapeHtml(p.period)}</td>
        <td><span class="badge" style="background:${statusBg};color:${statusColor}">${statusLabel}${daysStr}</span></td>
        <td style="font-size:12px">${paidDate}</td>
        <td style="font-size:12px">${expDate}</td>
        <td>${actions}</td>
      </tr>`;
    }).join('');

    // Pre-compute payment stats
    const activePayments = payments.filter(p => p.status === 'paid').length;
    const expiringSoon = payments.filter(p => p.status === 'paid' && p.expires_at && new Date(p.expires_at).getTime() < now + 3 * 86400000).length;
    const expiredPayments = payments.filter(p => p.status === 'expired').length;

    // Pre-compute user options for payment form
    const userOptions = users.map(u =>
      `<option value="${escapeHtml(u.id)}">${escapeHtml(u.email)} (${escapeHtml(u.tier)})</option>`
    ).join('');

    const userRows = users.map((u) => {
      const safeEmail = escapeHtml(u.email);
      const safeName = escapeHtml(u.name);
      const safeTier = escapeHtml(u.tier);
      const isTester = !!u.is_beta_tester;
      return `
      <tr>
        <td>${safeEmail}</td>
        <td>${safeName || '—'}</td>
        <td><span class="badge" style="background:${tierColor[u.tier] ?? '#6b7280'}20;color:${tierColor[u.tier] ?? '#6b7280'}">${safeTier}</span></td>
        <td>${u.tx_total}</td><td>${u.inv_total}</td>
        <td>${new Date(u.created_at).toLocaleDateString('ru-RU')}</td>
        <td>
          <select onchange="changeTier('${escapeHtml(u.id)}', this.value)">
            ${TIERS.map((t) =>
              `<option value="${t}"${t === u.tier ? ' selected' : ''}>${t}</option>`
            ).join('')}
          </select>
        </td>
        <td style="text-align:center">
          <label style="display:inline-flex;align-items:center;gap:6px;cursor:pointer;font-size:12px;color:${isTester ? '#16a34a' : '#9ca3af'};font-weight:600">
            <input type="checkbox" ${isTester ? 'checked' : ''} onchange="toggleBetaTester('${escapeHtml(u.id)}', this.checked)" style="cursor:pointer">
            ${isTester ? '🧪 тестер' : '—'}
          </label>
        </td>
      </tr>`;
    }).join('');

    const taxInputs = taxRows.map((r) => {
      const safeKey = escapeHtml(r.key);
      const safeLabel = escapeHtml(r.label);
      const safeValue = escapeHtml(r.value);
      return `
      <tr>
        <td style="font-size:12px;color:#6b7280;font-family:monospace">${safeKey}</td>
        <td>${safeLabel}</td>
        <td><input class="tax-input" data-key="${safeKey}" value="${safeValue}" style="width:100px;padding:4px 8px;border:1px solid #d1d5db;border-radius:6px;font-size:13px"></td>
        <td style="font-size:11px;color:#9ca3af">${r.updated_at ? new Date(r.updated_at).toLocaleDateString('ru-RU') : '—'}</td>
        <td><button onclick="saveTaxKey('${safeKey}')" style="padding:4px 10px;border:none;background:#2563eb;color:#fff;border-radius:6px;cursor:pointer;font-size:12px">Сохранить</button></td>
      </tr>`;
    }).join('');

    // Pre-compute feedback HTML
    // severity в БД: low / normal / high / critical (см. server/src/routes/feedback.js)
    const sevColor = {
      low:      { bg: '#dbeafe', fg: '#2563eb', label: '🔵 Низкая' },
      normal:   { bg: '#dcfce7', fg: '#16a34a', label: '🟢 Норм' },
      high:     { bg: '#fef3c7', fg: '#b45309', label: '🟠 Важно' },
      critical: { bg: '#fee2e2', fg: '#dc2626', label: '🔴 Критично' },
    };
    const sevFallback = { bg: '#f3f4f6', fg: '#6b7280', label: '—' };
    const statusColor = {
      new:         { bg: '#fef3c7', fg: '#b45309', label: 'Новый' },
      in_progress: { bg: '#dbeafe', fg: '#2563eb', label: 'В работе' },
      fixed:       { bg: '#dcfce7', fg: '#16a34a', label: 'Исправлен' },
      wontfix:     { bg: '#f3f4f6', fg: '#6b7280', label: 'Не будем' },
      duplicate:   { bg: '#f3f4f6', fg: '#6b7280', label: 'Дубль' },
    };
    const feedbackRows = feedback.map((f) => {
      const sev = sevColor[f.severity] ?? sevFallback;
      const st = statusColor[f.status] ?? statusColor.new;
      const safeId = escapeHtml(f.id);
      const dt = new Date(f.created_at);
      const dateStr = dt.toLocaleDateString('ru-RU') + ' ' + dt.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
      return `
      <tr>
        <td style="font-size:12px;white-space:nowrap">${dateStr}</td>
        <td style="font-size:12px">${escapeHtml(f.email)}<br/><span style="color:#9ca3af">${escapeHtml(f.name || '—')}</span></td>
        <td><span class="badge" style="background:${sev.bg};color:${sev.fg}">${sev.label}</span></td>
        <td style="font-size:12px;font-family:monospace;color:#6b7280">${escapeHtml(f.screen || '—')}</td>
        <td style="font-size:13px;max-width:420px">${escapeHtml(f.message)}</td>
        <td style="font-size:11px;color:#9ca3af">${escapeHtml(f.app_version || '—')}</td>
        <td>
          <select onchange="changeFeedbackStatus('${safeId}', this.value)" style="font-size:12px">
            ${['new','in_progress','fixed','wontfix','duplicate'].map(s =>
              `<option value="${s}"${s===f.status?' selected':''}>${statusColor[s].label}</option>`
            ).join('')}
          </select>
        </td>
      </tr>`;
    }).join('');

    const feedbackByStatus = {
      new:         feedback.filter(f => f.status === 'new').length,
      in_progress: feedback.filter(f => f.status === 'in_progress').length,
      fixed:       feedback.filter(f => f.status === 'fixed').length,
    };

    const artRows = arts.map((a) => {
      const safeTitle = escapeHtml(a.title);
      const safeSlug = escapeHtml(a.slug);
      const safeAudience = escapeHtml(a.audience);
      const safeStatus = escapeHtml(a.status);
      const safeId = escapeHtml(a.id);
      return `
      <tr>
        <td><a href="/api/articles/${safeSlug}" target="_blank" style="color:#2563eb;text-decoration:none">${safeTitle}</a></td>
        <td><span class="badge" style="background:#e0f2fe;color:#0369a1">${safeAudience}</span></td>
        <td><span class="badge" style="background:${a.status==='published'?'#dcfce7':'#fef3c7'};color:${a.status==='published'?'#16a34a':'#b45309'}">${safeStatus}</span></td>
        <td style="font-size:11px;color:#6b7280">${a.published_at ? new Date(a.published_at).toLocaleDateString('ru-RU') : '—'}</td>
        <td>
          <button onclick="publishArt('${safeId}','${safeStatus}')" style="padding:3px 8px;border:none;background:${a.status==='published'?'#fee2e2':'#dcfce7'};color:${a.status==='published'?'#dc2626':'#16a34a'};border-radius:5px;cursor:pointer;font-size:12px">
            ${a.status==='published' ? 'Снять' : 'Опубликовать'}
          </button>
          <button onclick="deleteArt('${safeId}')" style="padding:3px 8px;border:none;background:#fee2e2;color:#dc2626;border-radius:5px;cursor:pointer;font-size:12px;margin-left:4px">Удалить</button>
        </td>
      </tr>`;
    }).join('');

    res.send(`<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Esep Admin</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f8faff;color:#1a1a2e;padding:32px 24px}
    h1{font-size:22px;font-weight:700;margin-bottom:4px}
    h2{font-size:16px;font-weight:700;margin:32px 0 12px}
    .sub{color:#6b7280;font-size:13px;margin-bottom:24px}
    .stats{display:flex;gap:16px;margin-bottom:24px;flex-wrap:wrap}
    .stat{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:16px 20px;min-width:140px}
    .stat-val{font-size:24px;font-weight:700;color:#2563eb}
    .stat-label{font-size:12px;color:#6b7280;margin-top:2px}
    table{width:100%;background:#fff;border-radius:12px;border:1px solid #e5e7eb;border-collapse:collapse;overflow:hidden;margin-bottom:8px}
    th{background:#f1f5f9;padding:10px 14px;font-size:12px;font-weight:600;color:#6b7280;text-align:left}
    td{padding:10px 14px;font-size:13px;border-top:1px solid #f1f5f9;vertical-align:middle}
    tr:hover td{background:#fafbff}
    .badge{display:inline-block;padding:2px 10px;border-radius:20px;font-size:12px;font-weight:600}
    select{padding:4px 8px;border-radius:6px;border:1px solid #d1d5db;font-size:12px;cursor:pointer}
    .toast{position:fixed;bottom:24px;right:24px;background:#1a1a2e;color:#fff;padding:10px 18px;border-radius:8px;font-size:13px;display:none;z-index:999}
    .new-art{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:20px;margin-bottom:24px}
    .new-art input,.new-art select,.new-art textarea{width:100%;padding:8px 10px;border:1px solid #d1d5db;border-radius:8px;font-size:13px;margin-top:4px;font-family:inherit}
    .new-art textarea{min-height:120px;resize:vertical}
    .field{margin-bottom:12px}
    .field label{font-size:12px;color:#6b7280;font-weight:600}
    .btn-primary{padding:8px 20px;background:#2563eb;color:#fff;border:none;border-radius:8px;cursor:pointer;font-size:13px;font-weight:600}
    .nav{display:flex;gap:8px;margin-bottom:24px}
    .nav a{padding:6px 14px;border-radius:8px;font-size:13px;font-weight:600;text-decoration:none;color:#6b7280;background:#fff;border:1px solid #e5e7eb}
    .nav a.active,.nav a:hover{background:#2563eb;color:#fff;border-color:#2563eb}
  </style>
</head>
<body>
  <h1>Esep Admin</h1>
  <p class="sub">Управление пользователями, платежами, налогами и статьями</p>
  <nav class="nav">
    <a href="#users" class="active" onclick="showSection('users',this)">Пользователи</a>
    <a href="#payments" onclick="showSection('payments',this)">Платежи</a>
    <a href="#feedback" onclick="showSection('feedback',this)">🧪 Фидбек${feedbackByStatus.new > 0 ? ` <span style="background:#dc2626;color:#fff;border-radius:10px;padding:1px 7px;font-size:11px;margin-left:4px">${feedbackByStatus.new}</span>` : ''}</a>
    <a href="#course" onclick="showSection('course',this)">📚 Курс (черновик)</a>
    <a href="#tax" onclick="showSection('tax',this)">Налоговые ставки</a>
    <a href="#articles" onclick="showSection('articles',this)">Статьи</a>
    <a href="#promos" onclick="showSection('promos',this)">Промокоды</a>
  </nav>

  <!-- ── Users ── -->
  <div id="sec-users">
    <div class="stats">
      <div class="stat"><div class="stat-val">${users.length}</div><div class="stat-label">Всего</div></div>
      <div class="stat"><div class="stat-val">${users.filter(u=>u.tier==='free').length}</div><div class="stat-label">Бесплатный</div></div>
      <div class="stat"><div class="stat-val">${users.filter(u=>u.tier==='solo').length}</div><div class="stat-label">Solo</div></div>
      <div class="stat"><div class="stat-val">${users.filter(u=>u.tier==='accountant').length}</div><div class="stat-label">Бухгалтер</div></div>
      <div class="stat"><div class="stat-val">${users.filter(u=>u.tier==='accountant_pro').length}</div><div class="stat-label">Бухгалтер Про</div></div>
    </div>
    <table>
      <thead><tr><th>Email</th><th>Имя</th><th>Тариф</th><th>Транзакции</th><th>Счета</th><th>Регистрация</th><th>Сменить</th><th style="text-align:center">🧪 Тестер</th></tr></thead>
      <tbody>${userRows}</tbody>
    </table>
  </div>

  <!-- ── Payments ── -->
  <div id="sec-payments" style="display:none">
    <h2>Активировать тариф</h2>
    <div class="new-art" style="margin-bottom:24px">
      <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px">
        <div class="field"><label>Пользователь</label>
          <select id="pay-user">${userOptions}</select>
        </div>
        <div class="field"><label>Тариф</label>
          <select id="pay-tier">
            <option value="solo">Solo &mdash; от 2 000</option>
            <option value="accountant">Бухгалтер &mdash; 4 900</option>
            <option value="accountant_pro">Бухгалтер Про &mdash; 14 900</option>
          </select>
        </div>
        <div class="field"><label>Период</label>
          <select id="pay-period">
            <option value="monthly">1 месяц</option>
            <option value="quarterly">3 месяца</option>
            <option value="yearly">12 месяцев</option>
          </select>
        </div>
      </div>
      <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px;margin-top:12px">
        <div class="field"><label>Сумма (тенге)</label><input id="pay-amount" type="number" value="2000"></div>
        <div class="field"><label>Kaspi TXN ID</label><input id="pay-txn" placeholder="Номер чека"></div>
        <div class="field"><label>Примечание</label><input id="pay-note" placeholder="Из WhatsApp / чек #..."></div>
      </div>
      <button class="btn-primary" onclick="createPayment()" style="margin-top:12px">Активировать тариф</button>
    </div>

    <div class="stats">
      <div class="stat"><div class="stat-val">${activePayments}</div><div class="stat-label">Активных</div></div>
      <div class="stat"><div class="stat-val" style="color:#b45309">${expiringSoon}</div><div class="stat-label">Истекают скоро</div></div>
      <div class="stat"><div class="stat-val" style="color:#dc2626">${expiredPayments}</div><div class="stat-label">Истекших</div></div>
    </div>

    <h2>Все платежи</h2>
    <table>
      <thead><tr><th>Email</th><th>Тариф</th><th>Сумма</th><th>Период</th><th>Статус</th><th>Оплачено</th><th>Истекает</th><th>Действия</th></tr></thead>
      <tbody>${paymentRows}</tbody>
    </table>
  </div>

  <!-- ── Feedback ── -->
  <div id="sec-feedback" style="display:none">
    <h2>Багрепорты и предложения от тестеров</h2>
    <p style="font-size:13px;color:#6b7280;margin-bottom:16px">
      Сообщения от пользователей с галочкой «🧪 Тестер» через кнопку «Сообщить о баге» в приложении.
    </p>
    <div class="stats">
      <div class="stat"><div class="stat-val" style="color:#b45309">${feedbackByStatus.new}</div><div class="stat-label">Новые</div></div>
      <div class="stat"><div class="stat-val" style="color:#2563eb">${feedbackByStatus.in_progress}</div><div class="stat-label">В работе</div></div>
      <div class="stat"><div class="stat-val" style="color:#16a34a">${feedbackByStatus.fixed}</div><div class="stat-label">Исправлено</div></div>
      <div class="stat"><div class="stat-val">${feedback.length}</div><div class="stat-label">Всего</div></div>
    </div>
    ${feedback.length === 0
      ? `<div style="background:#fff;border:1px dashed #e5e7eb;border-radius:12px;padding:32px;text-align:center;color:#9ca3af">
          Пока нет фидбека. Включи тестеру галочку «🧪 Тестер» — у него появится кнопка «Сообщить о баге» на каждом экране.
        </div>`
      : `<table>
          <thead><tr>
            <th>Когда</th><th>Кто</th><th>Тип</th><th>Экран</th><th>Сообщение</th><th>Версия</th><th>Статус</th>
          </tr></thead>
          <tbody>${feedbackRows}</tbody>
        </table>`
    }
  </div>

  <!-- ── Course: 7 мини-уроков ── -->
  <div id="sec-course" style="display:none">
    <h2>Курс «Главные изменения НК 2026» — 7 мини-уроков</h2>
    <p style="font-size:13px;color:#6b7280;margin-bottom:16px">
      Раздел скрыт от публики (noindex, нет в навигации, нет в sitemap).
      Перепаписан с нуля 15.05.2026 — только проверенные факты из <code>kz_tax_constants.dart</code>,
      без сложной арифметики (вместо примеров — CTA в калькулятор Esep).
      Когда Фарида подтвердит — снимем noindex и опубликуем.
    </p>

    <div style="background:#fef9c3;border-left:4px solid #eab308;border-radius:10px;padding:14px 18px;margin-bottom:20px;font-size:13px;color:#713f12">
      <strong>Старые 13 статей и PDF-черновик</strong> перенесены в <code>esep-landing/nk2026/_drafts/</code>.
      Не публиковать — в них найдены критические ошибки (ОПВР, СН для ТОО, ГПХ vs трудовой, дивиденды).
      Подробности — в чате с проверкой 14.05.2026.
    </div>

    <div class="stats" style="margin-bottom:20px">
      <div class="stat">
        <div class="stat-val">7</div>
        <div class="stat-label">Мини-уроки</div>
      </div>
      <div class="stat">
        <div class="stat-val" style="color:#16a34a">7</div>
        <div class="stat-label">Готовы к проверке</div>
      </div>
      <div class="stat">
        <div class="stat-val" style="color:#dc2626">0</div>
        <div class="stat-label">Опубликовано</div>
      </div>
    </div>

    <h2 style="font-size:14px">Хаб</h2>
    <table>
      <thead><tr><th>Страница</th><th>Тип</th><th>Статус</th><th></th></tr></thead>
      <tbody>
        <tr>
          <td><strong>Главная курса</strong></td>
          <td><span class="badge" style="background:#e0f2fe;color:#0369a1">хаб</span></td>
          <td><span class="badge" style="background:#fef3c7;color:#b45309">скрыто (noindex)</span></td>
          <td><a href="https://esepkz.com/nk2026" target="_blank" style="color:#2563eb">Открыть →</a></td>
        </tr>
      </tbody>
    </table>

    <h2 style="font-size:14px;margin-top:20px">7 мини-уроков</h2>
    <table>
      <thead><tr><th>Урок</th><th>Тема</th><th>Статус</th><th></th></tr></thead>
      <tbody>
        ${[
          ['1', 'МРП и МЗП в 2026 — 4 325 и 85 000 ₸', 'mrp-mzp-2026'],
          ['2', 'НДС теперь 16% вместо 12%', 'nds-16-procentov'],
          ['3', 'Упрощёнка освобождена от НДС', 'uproshenka-bez-nds'],
          ['4', 'Базовый вычет ИПН — 30 МРП', 'vychet-ipn-30-mrp'],
          ['5', 'ОПВР работодателя — 3.5%', 'opvr-3-5-procenta'],
          ['6', 'СО и ВОСМС работодателя выросли', 'soc-platezhi-rabotodatel'],
          ['7', 'Новый лимит упрощёнки 910', 'limit-910-2026'],
        ].map(([num, title, slug]) => `
        <tr>
          <td><strong>Урок ${num}</strong></td>
          <td>${title}</td>
          <td><span class="badge" style="background:#dcfce7;color:#16a34a">ждёт проверки</span></td>
          <td><a href="https://esepkz.com/nk2026/${slug}" target="_blank" style="color:#2563eb">Открыть →</a></td>
        </tr>`).join('')}
      </tbody>
    </table>

    <div style="margin-top:24px;padding:16px 20px;background:#dbeafe;border-radius:10px;color:#1e40af;font-size:13px;line-height:1.6">
      <strong>План открытия раздела:</strong><br>
      1) Фарида проверяет 7 мини-уроков (короткие, без сложной арифметики — ~1 час) →<br>
      2) Снимаем <code>noindex</code> со всех 8 файлов (хаб + 7 уроков) →<br>
      3) Добавляем хаб /nk2026 в меню лендинга →<br>
      4) Добавляем URL в sitemap.xml →<br>
      5) Запускаем lead-magnet: рассылка по 165 лидам Connect + Instagram карусели + холодные касания
    </div>
  </div>

  <!-- ── Tax Config ── -->
  <div id="sec-tax" style="display:none">
    <h2>Налоговые ставки 2026</h2>
    <p style="font-size:13px;color:#6b7280;margin-bottom:16px">Изменения применяются сразу — приложение подтягивает через /api/config/tax</p>
    <table>
      <thead><tr><th>Ключ</th><th>Параметр</th><th>Значение</th><th>Обновлено</th><th></th></tr></thead>
      <tbody>${taxInputs}</tbody>
    </table>
  </div>

  <!-- ── Articles ── -->
  <div id="sec-articles" style="display:none">
    <h2>Новая статья</h2>
    <div class="new-art">
      <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px">
        <div class="field"><label>Slug (URL)</label><input id="a-slug" placeholder="nalog-ip-2026"></div>
        <div class="field"><label>Аудитория</label>
          <select id="a-audience">
            <option value="ip">ИП (простым языком)</option>
            <option value="accountant">Бухгалтер (техдайджест)</option>
            <option value="all">Все</option>
          </select>
        </div>
        <div class="field"><label>Статус</label>
          <select id="a-status">
            <option value="draft">Черновик</option>
            <option value="published">Опубликовать</option>
          </select>
        </div>
      </div>
      <div class="field"><label>Заголовок</label><input id="a-title" placeholder="Как платить налоги ИП в 2026 году"></div>
      <div class="field"><label>Краткое описание</label><input id="a-summary" placeholder="Понятное объяснение всех ставок и сроков"></div>
      <div class="field"><label>Текст (Markdown или HTML)</label><textarea id="a-body" placeholder="# Введение&#10;&#10;Текст статьи..."></textarea></div>
      <div class="field"><label>Теги (через запятую)</label><input id="a-tags" placeholder="упрощёнка, 910, налоги"></div>
      <button class="btn-primary" onclick="createArticle()">Создать статью</button>
    </div>
    <h2>Все статьи</h2>
    <table id="art-table">
      <thead><tr><th>Заголовок</th><th>Аудитория</th><th>Статус</th><th>Опубликовано</th><th>Действия</th></tr></thead>
      <tbody>${artRows}</tbody>
    </table>
  </div>

  <!-- ── Promos ── -->
  <div id="sec-promos" style="display:none">
    <h2>Создать промокод</h2>
    <div class="new-art" style="margin-bottom:24px">
      <div style="display:grid;grid-template-columns:1fr 1fr 1fr 1fr;gap:12px">
        <div class="field"><label>Код</label><input id="p-code" placeholder="REVIEW6" style="text-transform:uppercase"></div>
        <div class="field"><label>Тариф</label>
          <select id="p-tier">
            <option value="solo">Solo</option>
            <option value="accountant">Бухгалтер</option>
            <option value="accountant_pro">Бухгалтер Про</option>
          </select>
        </div>
        <div class="field"><label>Дней</label><input id="p-days" type="number" value="180" placeholder="180"></div>
        <div class="field"><label>Макс. использ. (0=безлимит)</label><input id="p-max" type="number" value="100"></div>
      </div>
      <div class="field"><label>Описание</label><input id="p-desc" placeholder="Отзыв = 6 мес бесплатно"></div>
      <button class="btn-primary" onclick="createPromo()">Создать промокод</button>
    </div>
    <h2>Все промокоды</h2>
    <table>
      <thead><tr><th>Код</th><th>Тариф</th><th>Дней</th><th>Использовано</th><th>Макс</th><th>Статус</th><th></th></tr></thead>
      <tbody>${promoRows}</tbody>
    </table>
  </div>

  <div class="toast" id="toast"></div>
  <script>
    const api  = (path, opts={}) => fetch(path, {
      headers: {'Content-Type':'application/json'},
      ...opts,
    });

    function showSection(id, el) {
      ['users','payments','feedback','course','tax','articles','promos'].forEach(s => {
        document.getElementById('sec-'+s).style.display = s===id ? '' : 'none';
      });
      document.querySelectorAll('.nav a').forEach(a => a.classList.remove('active'));
      el.classList.add('active');
    }
    // Handle hash on load
    const hash = location.hash.replace('#','');
    if (['payments','feedback','course','tax','articles','promos'].includes(hash)) {
      document.querySelectorAll('.nav a').forEach(a => {
        if (a.getAttribute('href')==='#'+hash) showSection(hash,a);
      });
    }

    function toast(msg, ok=true) {
      const t = document.getElementById('toast');
      t.textContent = msg;
      t.style.background = ok ? '#1a1a2e' : '#dc2626';
      t.style.display = 'block';
      setTimeout(() => t.style.display='none', 2500);
    }

    async function changeTier(userId, tier) {
      const r = await api('/api/admin/users/'+userId+'/tier', {
        method:'PATCH', body:JSON.stringify({tier})
      });
      toast(r.ok ? 'Тариф обновлён' : 'Ошибка', r.ok);
    }

    async function toggleBetaTester(userId, checked) {
      const r = await api('/api/admin/users/'+userId+'/beta-tester', {
        method:'PATCH', body:JSON.stringify({is: checked})
      });
      if (r.ok) {
        toast(checked ? '🧪 Включён режим тестировщика' : 'Режим тестировщика выключен', true);
        setTimeout(() => location.reload(), 600);
      } else {
        toast('Ошибка', false);
      }
    }

    async function saveTaxKey(key) {
      const val = document.querySelector('.tax-input[data-key="'+key+'"]').value;
      const r = await api('/api/config/tax/'+key, {
        method:'PUT', body:JSON.stringify({value:val})
      });
      toast(r.ok ? key+' сохранён' : 'Ошибка', r.ok);
    }

    async function createArticle() {
      const tags = document.getElementById('a-tags').value
        .split(',').map(t=>t.trim()).filter(Boolean);
      const r = await api('/api/articles', {
        method:'POST',
        body: JSON.stringify({
          slug:     document.getElementById('a-slug').value,
          title:    document.getElementById('a-title').value,
          summary:  document.getElementById('a-summary').value,
          body:     document.getElementById('a-body').value,
          audience: document.getElementById('a-audience').value,
          status:   document.getElementById('a-status').value,
          tags,
        }),
      });
      if (r.ok) { toast('Статья создана'); setTimeout(()=>location.reload(),1000); }
      else toast('Ошибка при создании', false);
    }

    async function publishArt(id, currentStatus) {
      const newStatus = currentStatus==='published' ? 'draft' : 'published';
      const r = await api('/api/articles/'+id, {
        method:'PUT', body:JSON.stringify({status:newStatus})
      });
      if (r.ok) { toast('Статус обновлён'); setTimeout(()=>location.reload(),800); }
      else toast('Ошибка', false);
    }

    async function deleteArt(id) {
      if (!confirm('Удалить статью?')) return;
      const r = await api('/api/articles/'+id, {method:'DELETE'});
      if (r.ok) { toast('Удалено'); setTimeout(()=>location.reload(),800); }
      else toast('Ошибка', false);
    }

    async function createPromo() {
      const r = await api('/api/promos', {
        method:'POST',
        body: JSON.stringify({
          code: document.getElementById('p-code').value,
          grant_tier: document.getElementById('p-tier').value,
          duration_days: parseInt(document.getElementById('p-days').value) || 180,
          max_uses: parseInt(document.getElementById('p-max').value) || 0,
          description: document.getElementById('p-desc').value,
        }),
      });
      if (r.ok) { toast('Промокод создан'); setTimeout(()=>location.reload(),1000); }
      else toast('Ошибка при создании', false);
    }

    async function deletePromo(id) {
      if (!confirm('Выключить промокод?')) return;
      const r = await api('/api/promos/'+id, {method:'DELETE'});
      if (r.ok) { toast('Промокод выключен'); setTimeout(()=>location.reload(),800); }
      else toast('Ошибка', false);
    }

    async function createPayment() {
      const r = await api('/api/admin/payments', {
        method:'POST',
        body: JSON.stringify({
          user_id: document.getElementById('pay-user').value,
          tier: document.getElementById('pay-tier').value,
          period: document.getElementById('pay-period').value,
          amount: parseFloat(document.getElementById('pay-amount').value) || 0,
          kaspi_txn_id: document.getElementById('pay-txn').value || null,
          note: document.getElementById('pay-note').value || null,
        }),
      });
      if (r.ok) { toast('Тариф активирован!'); setTimeout(()=>location.reload(),1000); }
      else toast('Ошибка при активации', false);
    }

    async function expirePayment(id) {
      if (!confirm('Закрыть подписку?')) return;
      const r = await api('/api/admin/payments/'+id+'/expire', {method:'PATCH'});
      if (r.ok) { toast('Подписка закрыта'); setTimeout(()=>location.reload(),800); }
      else toast('Ошибка', false);
    }

    async function extendPayment(id) {
      const r = await api('/api/admin/payments/'+id+'/extend', {
        method:'PATCH', body:JSON.stringify({months:1})
      });
      if (r.ok) { toast('Продлено на 1 месяц'); setTimeout(()=>location.reload(),800); }
      else toast('Ошибка', false);
    }

    async function changeFeedbackStatus(id, status) {
      const r = await api('/api/admin/feedback/'+id+'/status', {
        method:'PATCH', body:JSON.stringify({status})
      });
      toast(r.ok ? 'Статус обновлён' : 'Ошибка', r.ok);
    }
  </script>
</body>
</html>`);
  } catch (err) {
    console.error('GET /admin dashboard error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── Knowledge base management ────────────────────────────────────────────────

router.get('/api/admin/knowledge/stats', adminAuth, async (_req, res) => {
  try {
    const sources = await db.query(
      `SELECT source_type, COUNT(*) AS docs,
              COUNT(*) FILTER (WHERE is_active) AS active
         FROM knowledge_source
         GROUP BY source_type
         ORDER BY source_type`
    );
    const chunks = await db.query(
      `SELECT COUNT(*) AS total,
              COUNT(*) FILTER (WHERE embedding IS NOT NULL) AS with_embedding
         FROM knowledge_chunk`
    );
    res.json({
      sources: sources.rows,
      chunks: chunks.rows[0],
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/api/admin/knowledge/ingest/nk', adminAuth, async (_req, res) => {
  try {
    const { ingestNkRk } = require('../jobs/ingestNkRk');
    // Запускаем в фоне (может занять несколько минут)
    ingestNkRk()
      .then(r => console.log('[admin] NK ingest done:', r))
      .catch(e => console.error('[admin] NK ingest failed:', e));
    res.json({ status: 'started', message: 'НК ингестия запущена в фоне. Следите в логах.' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/api/admin/knowledge/reindex/platform', adminAuth, async (_req, res) => {
  try {
    const { seedEsepPlatformKnowledge } = require('../jobs/seedPlatformKnowledge');
    await seedEsepPlatformKnowledge();
    res.json({ status: 'done' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = { router, adminAuth };
