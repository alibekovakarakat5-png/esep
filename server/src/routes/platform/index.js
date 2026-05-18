/**
 * Platform API — точка входа для enterprise-клиентов.
 *
 * Доступ только по API-ключу (X-Platform-Key).
 * Каждый клиент получает свой набор разрешённых фич через таблицу platform_api_keys.
 *
 * Префикс: /api/platform
 *
 * Сервисы:
 *   POST /iin/validate              — #4 валидация ИИН (алгоритм)
 *   GET  /iin/validate/:iin
 *   GET  /taxpayer/:bin             — #2, #3 СНР, ОКЭД, статус ИП/ФЛ
 *   GET  /income-limit/status/:iin  — #7 текущий месячный лимит
 *   GET  /income-limit/check        — #7 предварительная проверка
 *   POST /income-limit/record       — #7 записать выплату
 *   POST /fiscalize/issue           — #1 фискализация (Webkassa) — TODO
 *   POST /fiscalize/cancel          — #5 аннулирование — TODO
 *   GET  /fiscalize/status/:id      — #6 статус чека — TODO
 *   GET  /self-employed/registry    — #8 реестр (ИСНА) — DEMO
 *   GET  /self-employed/benefits    — #9 льготы (ИСНА) — DEMO
 */

const express = require('express');
const router = express.Router();

const { requirePlatformKey } = require('../../middleware/platform_api_key');

// Sub-routers
const iinValidate = require('./iin_validate');
const taxpayerInfo = require('./taxpayer_info');
const incomeLimit = require('./income_limit');
const processPayment = require('./process_payment');
const cancelOrder = require('./cancel_order');
const webhooks = require('./webhooks');
const myAccount = require('./my_account');

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/platform — описание API
// (открыт без ключа, чтобы клиент мог увидеть какие сервисы доступны)
// ─────────────────────────────────────────────────────────────────────────────
router.get('/', (_req, res) => {
  res.json({
    api: 'Esep Platform API',
    version: '1.0.0-mvp',
    docs: 'https://api.esepkz.com/api/platform/docs',
    services: [
      { id: 'iin_validate', endpoint: 'POST /iin/validate', status: 'live', source: 'algorithm' },
      { id: 'taxpayer_info', endpoint: 'GET /taxpayer/:bin', status: 'live', source: 'stat.gov.kz' },
      { id: 'income_limit', endpoint: 'GET/POST /income-limit/*', status: 'live', source: 'our_db + НК 2026' },
      { id: 'fiscalize', endpoint: 'POST /fiscalize/issue', status: 'coming_soon', source: 'webkassa' },
      { id: 'cancel_receipt', endpoint: 'POST /fiscalize/cancel', status: 'coming_soon', source: 'webkassa' },
      { id: 'receipt_status', endpoint: 'GET /fiscalize/status/:id', status: 'coming_soon', source: 'webkassa' },
      { id: 'self_employed_registry', endpoint: 'GET /self-employed/registry', status: 'demo_mode', source: 'ISNA API (pending contract)' },
      { id: 'benefits', endpoint: 'GET /self-employed/benefits', status: 'demo_mode', source: 'ISNA API (pending contract)' },
    ],
    auth: {
      header: 'X-Platform-Key',
      description: 'Получить ключ можно у менеджера Esep',
    },
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/platform/me — проверить свой ключ (быстрый health check)
// ─────────────────────────────────────────────────────────────────────────────
router.get(
  '/me',
  requirePlatformKey(null), // без требования конкретной фичи
  (req, res) => {
    const c = req.platformClient;
    res.json({
      client: c.name,
      tier: c.tier,
      features: c.features,
      message: 'API-ключ валиден',
    });
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// Mount sub-routers
// ─────────────────────────────────────────────────────────────────────────────
router.use('/iin', iinValidate);
router.use('/taxpayer', taxpayerInfo);
router.use('/income-limit', incomeLimit);
router.use('/process-payment', processPayment);  // ← MAGIC endpoint для курьерки
router.use('/cancel-order', cancelOrder);        // ← Сервис #5 аннулирование
router.use('/webhooks', webhooks);               // ← приём уведомлений от Webkassa
router.use('/my-account', myAccount);            // ← для Flutter — JWT auth, не X-Platform-Key

// TODO: подключим когда напишу
// router.use('/fiscalize', fiscalize);
// router.use('/self-employed', selfEmployed);

// ─────────────────────────────────────────────────────────────────────────────
// Stubs для не-готовых сервисов — честная заглушка с пометкой demo_mode
// ─────────────────────────────────────────────────────────────────────────────
router.post(
  '/fiscalize/issue',
  requirePlatformKey('fiscalize'),
  (req, res) => {
    res.status(501).json({
      status: 'not_implemented',
      message: 'Эндпоинт в разработке. Интеграция с Webkassa API — следующий этап.',
      eta: '2-3 рабочих дня',
    });
  },
);

// /fiscalize/cancel — устарел, используйте /cancel-order
router.post(
  '/fiscalize/cancel',
  requirePlatformKey('cancel_receipt'),
  (_req, res) => {
    res.status(308).json({
      status: 'moved',
      message: 'Endpoint перенесён. Используйте POST /api/platform/cancel-order',
      new_url: '/api/platform/cancel-order',
    });
  },
);

router.get(
  '/fiscalize/status/:id',
  requirePlatformKey('receipt_status'),
  (req, res) => {
    res.status(501).json({
      status: 'not_implemented',
      message: 'Зависит от /fiscalize/issue.',
    });
  },
);

router.get(
  '/self-employed/registry',
  requirePlatformKey('self_employed_registry'),
  (req, res) => {
    res.json({
      mode: 'demo',
      warning: '⚠ Demo-данные. Реальный реестр требует подключения к API ИСНА (knp.kgd.gov.kz). Договор с КГД оформляется.',
      data: [
        // Демо-данные с явной пометкой
        { iin: '850101300123', name: 'Демо Курьер 1', status: 'active', registered_at: '2026-01-15', oked: '53201' },
        { iin: '900215400456', name: 'Демо Курьер 2', status: 'active', registered_at: '2026-02-20', oked: '53201' },
      ],
      total: 2,
      next_steps: 'Для production-данных необходим договор с КГД на API ИСНА. См. knpsd@ecc.kz',
    });
  },
);

router.get(
  '/self-employed/benefits/:iin',
  requirePlatformKey('benefits'),
  (req, res) => {
    res.json({
      mode: 'demo',
      iin: req.params.iin,
      warning: '⚠ Demo-данные. Реальные льготы доступны через API ИСНА после подключения.',
      benefits: [
        // Возможные категории по НК 2026 (закон 214-VIII)
        { code: 'youth', name: 'Молодёжь (до 29 лет)', applies: false },
        { code: 'multichild', name: 'Многодетная семья', applies: false },
        { code: 'disability', name: 'Инвалидность', applies: false },
        { code: 'large_family', name: 'Многодетная мать', applies: false },
      ],
      legal_basis: 'НК РК 2026, ст. о льготах самозанятых',
      next_steps: 'Реальное определение льгот возможно только через API ИСНА.',
    });
  },
);

module.exports = router;
