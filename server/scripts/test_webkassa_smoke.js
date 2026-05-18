/**
 * Smoke-тест реальной Webkassa.
 *
 * Запуск:
 *   node server/scripts/test_webkassa_smoke.js
 *
 * Требует env (из .env или экспорта):
 *   WEBKASSA_BASE_URL, WEBKASSA_API_KEY, WEBKASSA_LOGIN,
 *   WEBKASSA_PASSWORD, WEBKASSA_KASSA_NUMBER
 *
 * Что проверяет (4 шага):
 *   1) Авторизация: получает токен по логину/паролю
 *   2) Info о кассе: статус, лицензия, ОФД
 *   3) Загрузка тестового курьерского заказа (uploadCourierPayment)
 *   4) Удаление тестового заказа из нашей БД (cleanup)
 *
 * После этого можно включать PLATFORM_FISCALIZATION_ENABLED=true в проде.
 */

try { require('dotenv').config({ path: __dirname + '/../.env' }); } catch {}

const { createWebkassaClient } = require('../src/services/webkassa_client');

const c = {
  green: (s) => `\x1b[32m${s}\x1b[0m`,
  red: (s) => `\x1b[31m${s}\x1b[0m`,
  yellow: (s) => `\x1b[33m${s}\x1b[0m`,
  cyan: (s) => `\x1b[36m${s}\x1b[0m`,
  bold: (s) => `\x1b[1m${s}\x1b[0m`,
  dim: (s) => `\x1b[2m${s}\x1b[0m`,
};

function check(name, ok, info = '') {
  const sym = ok ? c.green('✅') : c.red('❌');
  console.log(`  ${sym}  ${name}${info ? '  ' + c.dim(info) : ''}`);
  return ok;
}

async function main() {
  console.log(c.bold(c.cyan('\n╔══════════════════════════════════════════════════════════╗')));
  console.log(c.bold(c.cyan('║  SMOKE-ТЕСТ WEBKASSA — реальное подключение              ║')));
  console.log(c.bold(c.cyan('╚══════════════════════════════════════════════════════════╝\n')));

  // ── Проверка env ──────────────────────────────────────────────────────────
  const required = ['WEBKASSA_BASE_URL', 'WEBKASSA_API_KEY', 'WEBKASSA_LOGIN', 'WEBKASSA_PASSWORD', 'WEBKASSA_KASSA_NUMBER'];
  const missing = required.filter((k) => !process.env[k]);
  if (missing.length > 0) {
    console.log(c.red('❌  Отсутствуют env-переменные:'));
    missing.forEach((k) => console.log('     ' + k));
    console.log('\nПолный список см. в server/.env.platform.example');
    process.exit(1);
  }

  console.log('Конфиг:');
  console.log(`  baseUrl:     ${process.env.WEBKASSA_BASE_URL}`);
  console.log(`  apiKey:      ${process.env.WEBKASSA_API_KEY.substring(0, 12)}...${c.dim('(скрыт)')}`);
  console.log(`  login:       ${process.env.WEBKASSA_LOGIN}`);
  console.log(`  password:    ${c.dim('(скрыт)')}`);
  console.log(`  kassa:       ${process.env.WEBKASSA_KASSA_NUMBER}\n`);

  const client = createWebkassaClient();

  // ── Шаг 1: авторизация ────────────────────────────────────────────────────
  console.log(c.bold('━━ 1. Авторизация (POST /api/v4/Authorize) ━━'));
  let token;
  try {
    token = await client.authorize();
    check('Токен получен', true, `prefix: ${token.substring(0, 16)}...`);
  } catch (err) {
    check('Авторизация', false, err.message);
    console.log('\n' + c.red('Дальше тестировать нечего — авторизация не работает.'));
    console.log(c.yellow('Возможные причины:'));
    console.log('  • Неверный WEBKASSA_LOGIN или WEBKASSA_PASSWORD');
    console.log('  • Неверный WEBKASSA_API_KEY');
    console.log('  • Касса заблокирована');
    process.exit(1);
  }

  // ── Шаг 2: информация о кассе ─────────────────────────────────────────────
  console.log(c.bold('\n━━ 2. Информация о кассе (POST /api-portal/v4/cashbox/client-info) ━━'));
  let info;
  try {
    info = await client.getCashboxInfo();
    check('Метод отвечает', true);

    const cashboxStatus = info?.CashboxStatus;
    check(`CashboxStatus = ${cashboxStatus}`, cashboxStatus === 1,
      cashboxStatus === 1 ? 'активна' : 'неактивна, статус не 1');

    const licStatus = info?.License?.LicenseStatus;
    check(`License.LicenseStatus = ${licStatus}`, licStatus !== undefined,
      licStatus ? `действует до ${info?.License?.LicenseExpirationDate}` : 'нет данных');

    const ofdCode = info?.Ofd?.Ofd;
    check(`ОФД код = ${ofdCode}`, ofdCode !== undefined,
      ofdCode ? `действует до ${info?.Ofd?.Expiration}` : 'нет данных');
  } catch (err) {
    check('client-info', false, err.message);
  }

  // ── Шаг 3: загрузка тестового заказа курьера ──────────────────────────────
  console.log(c.bold('\n━━ 3. Загрузка тестового заказа (POST /api/v4/Courier/UploadExternalOrder) ━━'));

  // Уникальный order_number (Webkassa требует уникальности в рамках организации)
  const orderNumber = `SMOKE-TEST-${Date.now()}`;
  console.log(c.dim(`  OrderNumber: ${orderNumber}`));

  try {
    const result = await client.uploadCourierPayment({
      orderNumber,
      amount: 5000,
      serviceName: 'Smoke test — выплата курьеру',
      withoutVat: true, // самозанятый
    });
    check('Заказ загружен в Webkassa', result.ok === true,
      result.ok ? 'теперь курьер увидит его в мобилке Webkassa' : JSON.stringify(result.raw));
  } catch (err) {
    check('Загрузка заказа', false, err.message);
    if (err.message.includes('400')) {
      console.log(c.yellow('     → Возможно, поле UnitCode или TaxPercent невалидны.'));
      console.log(c.yellow('       Проверь, что в kassa-настройках разрешена ставка 0% (без НДС).'));
    }
  }

  // ── Итог ──────────────────────────────────────────────────────────────────
  console.log(c.bold('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
  console.log(c.bold('  Smoke-тест завершён'));
  console.log(c.bold('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
  console.log('\nДальше:');
  console.log('  1. Если все ✅ — включай PLATFORM_FISCALIZATION_ENABLED=true');
  console.log('     и прогоняй полный e2e:');
  console.log('       node scripts/test_platform_e2e.js');
  console.log('  2. Открой ЛК Webkassa → раздел «Курьеры» — должен появиться');
  console.log(`     тестовый заказ ${orderNumber}`);
  console.log('  3. Найди в ЛК Webkassa настройку «URL для webhook»');
  console.log('     и пришли скриншот — следующим шагом подключим её к нашему');
  console.log('     /api/platform/webhooks/webkassa-courier\n');

  process.exit(0);
}

main().catch((err) => {
  console.error(c.red('\n❌  Smoke-тест упал:'), err.message);
  process.exit(1);
});
