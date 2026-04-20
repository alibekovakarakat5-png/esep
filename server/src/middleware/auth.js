const jwt = require('jsonwebtoken');
const db = require('../db');
const { normalizeTier } = require('../tiers');

module.exports = async (req, res, next) => {
  const auth = req.headers['authorization'] ?? '';
  if (!auth.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  try {
    const payload = jwt.verify(auth.slice(7), process.env.JWT_SECRET);
    req.userId = payload.sub;
    const { rows } = await db.query(
      'SELECT id, email, tier FROM users WHERE id = $1',
      [req.userId],
    );
    if (!rows.length) return res.status(401).json({ error: 'Invalid user' });
    req.user = {
      id: rows[0].id,
      email: rows[0].email,
      tier: normalizeTier(rows[0].tier),
    };
    next();
  } catch {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
};
