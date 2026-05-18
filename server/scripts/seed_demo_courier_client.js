/**
 * Создаёт демо-клиента «Курьерская служба» в Platform API.
 *
 * Запуск:
 *   node server/scripts/seed_demo_courier_client.js
 *
 * Опции через env:
 *   CLIENT_NAME      — имя клиента (по умолчанию "Demo Courier Service")
 *   CLIENT_BIN       — БИН клиента
 *   CONTACT_EMAIL    — email менеджера курьерки
 *
 * Что делает:
 *   1) Генерирует API-ключ формата demo_<random>
 *   2) Создаёт строку в platform_api_keys с включёнными всеми 9 фичами
 *   3) Выводит ключ в консоль — копируем и даём клиенту для тестирования
 */

require('dotenv').config({ path: __dirname + '/../.env' });
const crypto = require('crypto');
const db = require('../src/db');

const CLIENT_NAME = process.env.CLIENT_NAME || 'Demo Courier Service';
const CLIENT_BIN = process.env.CLIENT_BIN || null;
const CONTACT_EMAIL = process.env.CONTACT_EMAIL || null;

const ALL_FEATURES = [
  'iin_validate',           // #4
  'taxpayer_info',          // #2, #3
  'income_limit',           // #7
  'process_payment',        // MAGIC: всё в одном вызове
  'fiscalize',              // #1 — заглушка пока
  'cancel_receipt',         // #5 — заглушка пока
  'receipt_status',         // #6 — заглушка пока
  'self_employed_registry', // #8 — demo mode
  'benefits',               // #9 — demo mode
];

async function main() {
  // Генерация ключа: demo_ + 32 random hex chars
  const apiKey = 'demo_' + crypto.randomBytes(16).toString('hex');

  // Сначала убедимся, что таблица существует — может быть запускают до миграции
  try {
    const { migratePlatform } = require('../src/services/platform_db');
    await migratePlatform();
  } catch (err) {
    console.error('Не удалось выполнить миграцию:', err.message);
    process.exit(1);
  }

  // Вставляем
  const { rows } = await db.query(
    `INSERT INTO platform_api_keys
       (api_key, client_name, client_bin, tier, features,
        monthly_quota, contact_email, notes)
     VALUES ($1, $2, $3, 'enterprise', $4::jsonb, 10000, $5, $6)
     RETURNING id, created_at`,
    [
      apiKey,
      CLIENT_NAME,
      CLIENT_BIN,
      JSON.stringify(ALL_FEATURES),
      CONTACT_EMAIL,
      'Demo client для презентации курьерской службе. Все 9 сервисов включены, лимит 10 000 запросов/мес.',
    ],
  );

  console.log('\n╔══════════════════════════════════════════════════════════════════╗');
  console.log('║  ✅  DEMO КЛИЕНТ СОЗДАН                                          ║');
  console.log('╚══════════════════════════════════════════════════════════════════╝');
  console.log(`\nКлиент:        ${CLIENT_NAME}`);
  console.log(`ID:            ${rows[0].id}`);
  console.log(`БИН клиента:   ${CLIENT_BIN || '(не указан)'}`);
  console.log(`Создан:        ${rows[0].created_at}`);
  console.log(`Лимит:         10 000 запросов/мес`);
  console.log(`Доступ:        Все 9 сервисов\n`);
  console.log(`API-ключ:\n  ${apiKey}\n`);
  console.log('Использование:');
  console.log('  curl -H "X-Platform-Key: ' + apiKey + '" \\');
  console.log('       https://api.esepkz.com/api/platform/me');
  console.log('\nДоступные сервисы:');
  ALL_FEATURES.forEach((f, i) => console.log(`  ${i + 1}. ${f}`));
  console.log('');

  process.exit(0);
}

main().catch((err) => {
  console.error('❌  Ошибка:', err.message);
  process.exit(1);
});
