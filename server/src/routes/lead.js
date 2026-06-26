// Публичный приём заявок с лендингов (esepkz.com / buhfirma.esepkz.com).
// Без авторизации — поэтому валидируем + лёгкий rate-limit. Пишем в единую
// базу лидов и сразу уведомляем владельца в приватный Telegram-канал, чтобы
// НИ ОДНА заявка не терялась (раньше форма слала в Connect без apikey → 401).
const express = require('express');
const router = express.Router();
const { upsertLead, setLeadStatus, detectIntent } = require('../services/leads_db');
const tg = require('../bot/telegram');

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const clip = (v, n) => (v == null ? '' : String(v).trim().slice(0, n));

// Простая защита от спама: не более 8 заявок с одного IP в минуту.
const hits = new Map();
function rateLimited(ip) {
  const now = Date.now();
  const r = hits.get(ip) || { c: 0, reset: now + 60_000 };
  if (now > r.reset) { r.c = 0; r.reset = now + 60_000; }
  r.c++; hits.set(ip, r);
  if (hits.size > 5000) hits.clear(); // не растём бесконечно
  return r.c > 8;
}

router.post('/', async (req, res) => {
  const ip = String(req.headers['x-forwarded-for'] || req.ip || 'unknown').split(',')[0].trim();
  if (rateLimited(ip)) return res.status(429).json({ ok: false, error: 'too_many' });

  const b = req.body || {};
  const name      = clip(b.name, 120);
  const company   = clip(b.company, 160);
  const phone     = clip(b.phone, 40);
  const email     = clip(b.email, 160);
  const interest  = clip(b.interest, 80);
  const comment   = clip(b.comment, 600);
  const source    = clip(b.source, 60) || 'esep-landing';
  const sourceUrl = clip(b.sourceUrl, 300);

  // Honeypot (скрытое поле, заполняют только боты) → молча игнорируем.
  if (clip(b.website, 50) || clip(b._gotcha, 50)) return res.json({ ok: true });
  if (!phone && !email && !name) return res.status(400).json({ ok: false, error: 'empty' });

  const intent = detectIntent([interest, comment, company].join(' '));

  // 1) Единая база лидов (дедуп по телефону). Не валим ответ при ошибке.
  let leadId = null;
  try {
    leadId = await upsertLead({ phone, name: name || null, source, intent });
    if (leadId) {
      const notes = [
        company   && `Компания: ${company}`,
        email     && `Email: ${email}`,
        interest  && `Интерес: ${interest}`,
        comment   && `Коммент: ${comment}`,
        sourceUrl && `URL: ${sourceUrl}`,
      ].filter(Boolean).join(' · ');
      if (notes) await setLeadStatus(leadId, 'new', notes);
    }
  } catch (e) {
    console.error('[lead] save error:', e.message);
  }

  // 2) Уведомление владельцу — даже если запись в БД не удалась (плохой телефон).
  try {
    const msg = [
      '🟢 <b>Новая заявка с лендинга</b>',
      name     && `👤 ${esc(name)}`,
      company  && `🏢 ${esc(company)}`,
      phone    && `📞 ${esc(phone)}`,
      email    && `✉️ ${esc(email)}`,
      interest && `💼 ${esc(interest)}`,
      comment  && `💬 ${esc(comment)}`,
      `🔗 <i>${esc(source)}</i>${leadId ? ` · лид #${leadId}` : ''}`,
    ].filter(Boolean).join('\n');
    await tg.sendToPrivate(msg);
  } catch (e) {
    console.error('[lead] notify error:', e.message);
  }

  res.json({ ok: true, id: leadId });
});

module.exports = router;
