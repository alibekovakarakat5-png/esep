/**
 * Platform Service #4: Валидация ИИН
 *
 * Endpoint: POST /api/platform/iin/validate
 * Body: { "iin": "850101300123" }
 *
 * Возвращает:
 *   { valid: boolean, reason: string|null, details: {...} }
 *
 * Использует чистый алгоритм (Постановление № 853 от 26.08.2013).
 * НЕ ходит в КГД — это математическая проверка контрольной цифры.
 *
 * Для боевой проверки "существует ли такой ИИН в реестре КГД"
 * клиент должен дополнительно вызвать /api/platform/taxpayer
 * (он использует stat.gov.kz API).
 */

const express = require('express');
const router = express.Router();
const { validateIinChecksum } = require('../../services/iin_algorithm');

// POST /api/platform/iin/validate
router.post('/validate', (req, res) => {
  const { iin } = req.body || {};

  if (!iin) {
    return res.status(400).json({
      error: 'Поле "iin" обязательно',
      example: { iin: '850101300123' },
    });
  }

  const result = validateIinChecksum(String(iin).trim());

  return res.json({
    iin: String(iin).trim(),
    ...result,
    source: 'algorithm', // не из реестра — чистый расчёт
    docs: 'Постановление Правительства РК № 853 от 26.08.2013',
  });
});

// GET /api/platform/iin/validate/:iin (для удобства тестирования через браузер)
router.get('/validate/:iin', (req, res) => {
  const { iin } = req.params;
  const result = validateIinChecksum(String(iin).trim());

  return res.json({
    iin: String(iin).trim(),
    ...result,
    source: 'algorithm',
    docs: 'Постановление Правительства РК № 853 от 26.08.2013',
  });
});

module.exports = router;
