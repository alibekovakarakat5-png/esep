/**
 * Создаёт enterprise-юзера в Esep:
 *   1) User с tier='enterprise' (можно логиниться через email/пароль)
 *   2) Связанный platform_api_keys с включёнными всеми 9 сервисами
 *
 * Запуск:
 *   node server/scripts/seed_courier_enterprise.js
 *
 * env:
 *   EMAIL          — email клиента (логин)
 *   PASSWORD       — пароль (или генерируется случайный)
 *   COMPANY_NAME   — название компании
 *   COMPANY_BIN    — БИН клиента
 *   MONTHLY_QUOTA  — лимит запросов в месяц (по умолчанию 10000)
 */

try { require('dotenv').config({ path: __dirname + '/../.env' }); } catch {}
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const db = require('../src/db');

const EMAIL         = process.env.EMAIL         || 'courier-demo@esepkz.com';
const PASSWORD      = process.env.PASSWORD      || 'CourierDemo2026!';
const COMPANY_NAME  = process.env.COMPANY_NAME  || 'ТОО "Демо Курьерская Служба"';
const COMPANY_BIN   = process.env.COMPANY_BIN   || null;
const MONTHLY_QUOTA = parseInt(process.env.MONTHLY_QUOTA || '10000', 10);

const ALL_FEATURES = [
  'iin_validate',
  'taxpayer_info',
  'income_limit',
  'process_payment',
  'fiscalize',
  'cancel_receipt',
  'receipt_status',
  'self_employed_registry',
  'benefits',
];

async function main() {
  // Сначала миграция (если БД свежая)
  try {
    const { migratePlatform } = require('../src/services/platform_db');
    await migratePlatform();
  } catch (err) {
    console.error('Миграция упала:', err.message);
    process.exit(1);
  }

  // 1) Создаём User
  const passwordHash = await bcrypt.hash(PASSWORD, 10);

  let userId;
  try {
    const { rows } = await db.query(
      `INSERT INTO users (email, name, password_hash, tier)
       VALUES ($1, $2, $3, 'enterprise')
       ON CONFLICT (email) DO UPDATE SET
         tier = 'enterprise',
         password_hash = EXCLUDED.password_hash
       RETURNING id, email, tier`,
      [EMAIL, COMPANY_NAME, passwordHash],
    );
    userId = rows[0].id;
    console.log(`✅ User создан/обновлён: ${rows[0].email}, tier=${rows[0].tier}`);
  } catch (err) {
    console.error('Не смог создать User:', err.message);
    process.exit(1);
  }

  // 2) Удаляем старые активные ключи для этого юзера (чтобы не плодить)
  await db.query(
    `UPDATE platform_api_keys SET is_active = FALSE WHERE user_id = $1`,
    [userId],
  );

  // 3) Создаём новый platform_api_key
  const apiKey = 'wkc_' + crypto.randomBytes(20).toString('hex');
  await db.query(
    `INSERT INTO platform_api_keys
       (user_id, api_key, client_name, client_bin, tier, features,
        monthly_quota, contact_email, notes, is_active)
     VALUES ($1, $2, $3, $4, 'enterprise', $5::jsonb,
             $6, $7, $8, TRUE)`,
    [
      userId,
      apiKey,
      COMPANY_NAME,
      COMPANY_BIN,
      JSON.stringify(ALL_FEATURES),
      MONTHLY_QUOTA,
      EMAIL,
      `Enterprise клиент. Логин в Esep: ${EMAIL}`,
    ],
  );

  console.log('\n╔══════════════════════════════════════════════════════════════════╗');
  console.log('║  ✅  ENTERPRISE КЛИЕНТ ГОТОВ                                     ║');
  console.log('╚══════════════════════════════════════════════════════════════════╝');
  console.log(`\nКомпания:    ${COMPANY_NAME}`);
  console.log(`БИН:         ${COMPANY_BIN || '(не указан)'}`);
  console.log(`\n── Доступ для клиента в Esep app ─────────────────────────`);
  console.log(`Логин:       ${EMAIL}`);
  console.log(`Пароль:      ${PASSWORD}`);
  console.log(`\n── Доступ для интеграции (API) ───────────────────────────`);
  console.log(`API Base:    https://api.esepkz.com/api/platform`);
  console.log(`API Key:     ${apiKey}`);
  console.log(`Лимит:       ${MONTHLY_QUOTA} запросов в месяц`);
  console.log(`\nПри логине в Esep этот юзер увидит Platform Dashboard,`);
  console.log(`а не обычный учёт/счета.\n`);

  process.exit(0);
}

main().catch((err) => {
  console.error('❌  Ошибка:', err.message);
  process.exit(1);
});
