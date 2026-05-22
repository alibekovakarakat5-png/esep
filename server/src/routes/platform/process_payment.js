/**
 * Platform MAGIC Endpoint: «Обработать выплату курьеру»
 *
 * Это ЕДИНСТВЕННЫЙ endpoint, который клиент-курьерка должен вызывать
 * на каждую выплату. Внутри мы делаем всё:
 *   1) Валидируем ИИН курьера (алгоритм)
 *   2) Проверяем СНР/ОКЭД (stat.gov.kz)
 *   3) Проверяем лимит 300 МРП в месяце
 *   4) Записываем выплату в наш учёт
 *   5) Ставим в очередь на фискализацию (когда Webkassa подключим — отправим)
 *
 * Endpoint: POST /api/platform/process-payment
 * Body:
 *   {
 *     "courier_iin": "850101300123",   // обязательно
 *     "amount": 50000,                   // обязательно, в тенге
 *     "order_id": "ORD-2026-05-18-123",  // обязательно, ID заказа в их системе
 *     "payment_method": "card",          // опционально
 *     "skip_taxpayer_check": false       // если true — не зовём stat.gov.kz (для скорости)
 *   }
 *
 * Возвращаем единый ответ:
 *   {
 *     "ok": true,
 *     "decision": "PROCEED" | "BLOCK" | "WARNING",
 *     "iin_valid": true,
 *     "taxpayer": { ... } | null,
 *     "income_limit": { used, remaining, percent },
 *     "fiscal_status": "queued" | "issued",
 *     "warnings": [...],
 *     "errors": [...]
 *   }
 *
 * Клиент по полю `decision` за миллисекунду понимает что делать:
 *   PROCEED — платить курьеру можно
 *   BLOCK   — нельзя (превышен лимит / неверный ИИН / курьер не самозанятый)
 *   WARNING — можно, но обратить внимание (лимит близок к исчерпанию)
 */

const express = require('express');
const https = require('https');
const router = express.Router();

const { requirePlatformKey } = require('../../middleware/platform_api_key');
const { validateIinChecksum } = require('../../services/iin_algorithm');
const {
  getMonthlyIncome,
  recordIncome,
} = require('../../services/platform_db');
const { createWebkassaClient } = require('../../services/webkassa_client');
const db = require('../../db');

// Включена ли реальная фискализация (true = идём в Webkassa, false = только queue)
const FISCALIZATION_ENABLED = process.env.PLATFORM_FISCALIZATION_ENABLED === 'true';

const MRP_2026 = 4325;
const MONTHLY_LIMIT_TENGE = 300 * MRP_2026; // 1 297 500 ₸

// Кэш stat.gov.kz (тот же, что в taxpayer_info.js — TODO вынести в общий модуль)
const taxpayerCache = new Map();
const CACHE_TTL = 60 * 60 * 1000;

function getCachedTaxpayer(bin) {
  const e = taxpayerCache.get(bin);
  if (!e) return null;
  if (Date.now() - e.ts > CACHE_TTL) {
    taxpayerCache.delete(bin);
    return null;
  }
  return e.data;
}

function setCachedTaxpayer(bin, data) {
  taxpayerCache.set(bin, { data, ts: Date.now() });
}

function fetchTaxpayer(bin) {
  return new Promise((resolve) => {
    const cached = getCachedTaxpayer(bin);
    if (cached) return resolve(cached);

    const url = `https://old.stat.gov.kz/api/juridical/counter/api/?bin=${bin}&lang=ru`;
    const req = https.get(url, { timeout: 5000 }, (res) => {
      if (res.statusCode !== 200) return resolve(null);
      let buf = '';
      res.on('data', (c) => (buf += c));
      res.on('end', () => {
        try {
          const json = JSON.parse(buf);
          setCachedTaxpayer(bin, json);
          resolve(json);
        } catch {
          resolve(null);
        }
      });
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => {
      req.destroy();
      resolve(null);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/platform/process-payment
// ─────────────────────────────────────────────────────────────────────────────
router.post(
  '/',
  requirePlatformKey('process_payment'),
  async (req, res) => {
    const startedAt = Date.now();
    const {
      courier_iin,
      amount,
      order_id,
      payment_method = 'unknown',
      skip_taxpayer_check = false,
    } = req.body || {};

    const result = {
      ok: false,
      decision: 'BLOCK',
      iin_valid: false,
      taxpayer: null,
      income_limit: null,
      fiscal_status: null,
      warnings: [],
      errors: [],
      processed_in_ms: 0,
    };

    // ── 1. Валидация входа ──────────────────────────────────────────────────
    if (!courier_iin || !amount || !order_id) {
      result.errors.push('Поля "courier_iin", "amount", "order_id" обязательны');
      result.processed_in_ms = Date.now() - startedAt;
      return res.status(400).json(result);
    }

    const amountNum = parseFloat(amount);
    if (!Number.isFinite(amountNum) || amountNum <= 0) {
      result.errors.push('"amount" должен быть числом > 0');
      result.processed_in_ms = Date.now() - startedAt;
      return res.status(400).json(result);
    }

    // ── 2. Валидация ИИН (алгоритм) ─────────────────────────────────────────
    const iinCheck = validateIinChecksum(String(courier_iin).trim());
    if (!iinCheck.valid) {
      result.errors.push(`Неверный ИИН: ${iinCheck.reason}`);
      result.processed_in_ms = Date.now() - startedAt;
      return res.status(400).json(result);
    }
    result.iin_valid = true;

    // ── 2b. Идемпотентность ─────────────────────────────────────────────────
    // Если заказ с этим order_id уже обрабатывался — возвращаем прежний
    // результат и НЕ регистрируем выплату повторно. Защита от ретраев
    // клиента после таймаута (иначе задваивается учёт лимита 300 МРП).
    try {
      const dup = await db.query(
        `SELECT status FROM platform_receipts
          WHERE api_key_id = $1 AND external_id = $2
          LIMIT 1`,
        [req.platformClient.id, order_id],
      );
      if (dup.rows.length > 0) {
        result.ok = true;
        result.decision = 'PROCEED';
        result.idempotent_replay = true;
        result.fiscal_status = dup.rows[0].status;
        result.warnings.push(
          'Заказ с этим order_id уже обработан ранее. Возвращён прежний ' +
          'результат, повторная выплата не зарегистрирована.',
        );
        result.processed_in_ms = Date.now() - startedAt;
        return res.status(200).json(result);
      }
    } catch (err) {
      // Сбой проверки не должен блокировать платёж — продолжаем обычным путём.
      result.warnings.push('Проверка идемпотентности не выполнена: ' + err.message);
    }

    // ── 3. Проверка СНР/ОКЭД (если не пропустили) ───────────────────────────
    if (!skip_taxpayer_check) {
      try {
        const taxpayerRaw = await fetchTaxpayer(courier_iin);
        if (taxpayerRaw) {
          const obj = taxpayerRaw?.obj || taxpayerRaw;
          result.taxpayer = {
            name: obj?.name || obj?.NameRu || null,
            is_ip: courier_iin.substring(4, 6).startsWith('3'),
            oked_code: obj?.okedCode || null,
            oked_name: obj?.okedName || null,
            found_in_registry: Boolean(obj?.name || obj?.NameRu),
          };

          // Бизнес-правило: курьер должен быть либо ФЛ-самозанятым,
          // либо ИП (не ТОО)
          if (result.taxpayer.is_ip === false && result.taxpayer.found_in_registry) {
            result.warnings.push(
              'Курьер зарегистрирован как ТОО, не ИП и не самозанятый. ' +
              'Проверьте правомерность выплаты на ИИН вместо БИН.'
            );
          }
        } else {
          result.warnings.push('Не удалось проверить курьера в реестре stat.gov.kz (таймаут или 403). Продолжаем без этого шага.');
        }
      } catch (err) {
        result.warnings.push('Ошибка проверки реестра: ' + err.message);
      }
    }

    // ── 4. Проверка лимита 300 МРП ──────────────────────────────────────────
    let used = 0;
    try {
      used = await getMonthlyIncome(courier_iin);
    } catch (err) {
      result.errors.push('Ошибка БД при проверке лимита: ' + err.message);
      result.processed_in_ms = Date.now() - startedAt;
      return res.status(500).json(result);
    }

    const afterPayment = used + amountNum;
    const percentUsed = Math.min(100, (afterPayment / MONTHLY_LIMIT_TENGE) * 100);

    result.income_limit = {
      used_before: used,
      proposed_amount: amountNum,
      would_be_total: afterPayment,
      limit: MONTHLY_LIMIT_TENGE,
      percent_used_after: parseFloat(percentUsed.toFixed(2)),
      remaining_after: Math.max(0, MONTHLY_LIMIT_TENGE - afterPayment),
    };

    if (afterPayment > MONTHLY_LIMIT_TENGE) {
      result.errors.push(
        `Превышение лимита 300 МРП. ` +
        `Уже выплачено в этом месяце: ${used} ₸, ` +
        `с этой выплатой будет: ${afterPayment} ₸, ` +
        `лимит: ${MONTHLY_LIMIT_TENGE} ₸. ` +
        `Курьер должен зарегистрироваться как ИП.`
      );
      result.decision = 'BLOCK';
      result.processed_in_ms = Date.now() - startedAt;
      return res.status(409).json(result);
    }

    if (percentUsed >= 80) {
      result.warnings.push(
        `Курьер близок к месячному лимиту (${percentUsed.toFixed(1)}% от 300 МРП). ` +
        `Рекомендуем предупредить его о переходе в ИП.`
      );
    }

    // ── 5. Запись выплаты ───────────────────────────────────────────────────
    try {
      await recordIncome({
        apiKeyId: req.platformClient.id,
        iin: courier_iin,
        amount: amountNum,
        externalId: order_id,
        paymentMethod: payment_method,
        note: `Auto via /process-payment`,
      });
    } catch (err) {
      result.errors.push('Ошибка записи выплаты: ' + err.message);
      result.processed_in_ms = Date.now() - startedAt;
      return res.status(500).json(result);
    }

    // ── 6. Загрузка предзаказа в Webkassa (платформенная фискализация) ──────
    // Архитектура (см. webkassa_client.js):
    //   Мы → uploadCourierOrder → Webkassa
    //   Курьер в мобилке → фискализирует → Webkassa регистрирует в КГД
    //   Webkassa → webhook на наш URL → мы обновляем status='issued'
    let webkassaUploaded = false;
    let webkassaError = null;

    if (FISCALIZATION_ENABLED) {
      try {
        const webkassa = createWebkassaClient();
        await webkassa.uploadCourierPayment({
          orderNumber: order_id,
          amount: amountNum,
          serviceName: 'Услуги доставки',
          // CustomerPhone/Email можно добавить если клиент пришлёт
          withoutVat: true, // курьер-самозанятый → без НДС
        });
        webkassaUploaded = true;
      } catch (err) {
        webkassaError = err.message;
        result.warnings.push('Не удалось загрузить заказ в Webkassa: ' + err.message);
      }
    } else {
      result.warnings.push(
        'Фискализация отключена флагом PLATFORM_FISCALIZATION_ENABLED. ' +
        'Чек поставлен в очередь до включения флага.'
      );
    }

    // ── 7. Запись чека в нашу БД (в любом случае) ──────────────────────────
    try {
      await db.query(
        `INSERT INTO platform_receipts
           (api_key_id, external_id, iin, amount, ofd_provider, status, raw_response)
         VALUES ($1, $2, $3, $4, 'webkassa', $5, $6::jsonb)`,
        [
          req.platformClient.id,
          order_id,
          courier_iin,
          amountNum,
          webkassaUploaded ? 'awaiting_courier_fiscalization' :
            (FISCALIZATION_ENABLED ? 'upload_failed' : 'pending_ofd_contract'),
          JSON.stringify({
            uploaded_to_webkassa: webkassaUploaded,
            webkassa_error: webkassaError,
            uploaded_at: new Date().toISOString(),
          }),
        ],
      );

      if (webkassaUploaded) {
        result.fiscal_status = 'awaiting_courier_fiscalization';
        // Информационное поле для курьерки
        result.fiscal_info = {
          message: 'Заказ загружен в Webkassa. Курьер фискализирует чек через приложение Webkassa при доставке.',
          callback: 'Уведомление о фискализации придёт на ваш webhook.',
        };
      } else if (FISCALIZATION_ENABLED) {
        result.fiscal_status = 'upload_failed';
      } else {
        result.fiscal_status = 'queued';
      }
    } catch (err) {
      result.warnings.push('Чек не записан в БД: ' + err.message);
      result.fiscal_status = 'failed';
    }

    // ── 7. Итог ─────────────────────────────────────────────────────────────
    result.ok = true;
    result.decision = result.warnings.length > 0 ? 'WARNING' : 'PROCEED';
    result.processed_in_ms = Date.now() - startedAt;

    return res.status(200).json(result);
  },
);

module.exports = router;
