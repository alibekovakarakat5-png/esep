const router = require('express').Router();
const db     = require('../db');

const TIERS = ['free', 'ip', 'accountant', 'corporate'];

// ── Simple password middleware ────────────────────────────────────────────────
function adminAuth(req, res, next) {
  const pass = process.env.ADMIN_PASSWORD;
  if (!pass) return res.status(500).send('ADMIN_PASSWORD not set');

  const auth = req.headers['authorization'] ?? '';
  // Basic auth: Authorization: Bearer <password>
  if (auth === `Bearer ${pass}`) return next();

  // Also allow ?pass=... for browser convenience
  if (req.query.pass === pass) return next();

  res.status(401).json({ error: 'Unauthorized' });
}

// ── GET /api/admin/users ──────────────────────────────────────────────────────
router.get('/users', adminAuth, async (req, res) => {
  const { rows } = await db.query(
    `SELECT id, email, name, tier, created_at,
            (SELECT COUNT(*) FROM transactions WHERE user_id = users.id) AS tx_total,
            (SELECT COUNT(*) FROM invoices   WHERE user_id = users.id) AS inv_total
     FROM users
     ORDER BY created_at DESC`,
  );
  res.json(rows);
});

// ── PATCH /api/admin/users/:id/tier ──────────────────────────────────────────
router.patch('/users/:id/tier', adminAuth, async (req, res) => {
  const { tier } = req.body ?? {};
  if (!TIERS.includes(tier)) {
    return res.status(400).json({ error: `tier must be one of: ${TIERS.join(', ')}` });
  }
  await db.query('UPDATE users SET tier = $1 WHERE id = $2', [tier, req.params.id]);
  res.json({ ok: true });
});

// ── GET /api/admin — HTML dashboard ──────────────────────────────────────────
router.get('/', adminAuth, async (_req, res) => {
  const { rows: users } = await db.query(
    `SELECT id, email, name, tier, created_at,
            (SELECT COUNT(*) FROM transactions WHERE user_id = users.id) AS tx_total,
            (SELECT COUNT(*) FROM invoices   WHERE user_id = users.id) AS inv_total
     FROM users
     ORDER BY created_at DESC`,
  );

  const tierColor = { free: '#6b7280', ip: '#2563eb', accountant: '#7c3aed', corporate: '#d97706' };
  const rows = users.map((u) => `
    <tr>
      <td>${u.email}</td>
      <td>${u.name || '—'}</td>
      <td>
        <span class="badge" style="background:${tierColor[u.tier] ?? '#6b7280'}20;color:${tierColor[u.tier] ?? '#6b7280'}">${u.tier}</span>
      </td>
      <td>${u.tx_total}</td>
      <td>${u.inv_total}</td>
      <td>${new Date(u.created_at).toLocaleDateString('ru-RU')}</td>
      <td>
        <select onchange="changeTier('${u.id}', this.value)">
          ${['free','ip','accountant','corporate'].map((t) =>
            `<option value="${t}"${t === u.tier ? ' selected' : ''}>${t}</option>`
          ).join('')}
        </select>
      </td>
    </tr>
  `).join('');

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
    .sub{color:#6b7280;font-size:13px;margin-bottom:24px}
    .stats{display:flex;gap:16px;margin-bottom:24px;flex-wrap:wrap}
    .stat{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:16px 20px;min-width:140px}
    .stat-val{font-size:24px;font-weight:700;color:#2563eb}
    .stat-label{font-size:12px;color:#6b7280;margin-top:2px}
    table{width:100%;background:#fff;border-radius:12px;border:1px solid #e5e7eb;border-collapse:collapse;overflow:hidden}
    th{background:#f1f5f9;padding:10px 14px;font-size:12px;font-weight:600;color:#6b7280;text-align:left}
    td{padding:10px 14px;font-size:13px;border-top:1px solid #f1f5f9}
    tr:hover td{background:#fafbff}
    .badge{display:inline-block;padding:2px 10px;border-radius:20px;font-size:12px;font-weight:600}
    select{padding:4px 8px;border-radius:6px;border:1px solid #d1d5db;font-size:12px;cursor:pointer}
    .toast{position:fixed;bottom:24px;right:24px;background:#1a1a2e;color:#fff;padding:10px 18px;border-radius:8px;font-size:13px;display:none}
  </style>
</head>
<body>
  <h1>Esep Admin</h1>
  <p class="sub">Управление пользователями и тарифами</p>
  <div class="stats">
    <div class="stat"><div class="stat-val">${users.length}</div><div class="stat-label">Всего пользователей</div></div>
    <div class="stat"><div class="stat-val">${users.filter(u=>u.tier==='free').length}</div><div class="stat-label">Бесплатный</div></div>
    <div class="stat"><div class="stat-val">${users.filter(u=>u.tier==='ip').length}</div><div class="stat-label">ИП (1 990 ₸)</div></div>
    <div class="stat"><div class="stat-val">${users.filter(u=>u.tier==='accountant').length}</div><div class="stat-label">Бухгалтер (7 990 ₸)</div></div>
    <div class="stat"><div class="stat-val">${users.filter(u=>u.tier==='corporate').length}</div><div class="stat-label">Корпоративный</div></div>
  </div>
  <table>
    <thead>
      <tr>
        <th>Email</th><th>Имя</th><th>Тариф</th><th>Транзакции</th><th>Счета</th><th>Дата регистрации</th><th>Сменить тариф</th>
      </tr>
    </thead>
    <tbody>${rows}</tbody>
  </table>
  <div class="toast" id="toast"></div>
  <script>
    const pass = new URLSearchParams(location.search).get('pass') || '';
    async function changeTier(userId, tier) {
      const r = await fetch('/api/admin/users/' + userId + '/tier?pass=' + pass, {
        method: 'PATCH',
        headers: {'Content-Type':'application/json'},
        body: JSON.stringify({ tier }),
      });
      const t = document.getElementById('toast');
      t.textContent = r.ok ? 'Тариф обновлён ✓' : 'Ошибка';
      t.style.display = 'block';
      setTimeout(() => t.style.display = 'none', 2000);
    }
  </script>
</body>
</html>`);
});

module.exports = { router, adminAuth };
