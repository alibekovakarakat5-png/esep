/**
 * Webkassa Client — ОФД для фискализации чеков (Сервисы 1, 5, 6 Platform API).
 *
 * Базируется на Webkassa Integrators API v4-2.0.3
 * Документация: https://documenter.getpostman.com/view/48749526/2sBXc8o3JF
 *
 * Особенности API Webkassa, выявленные из документации:
 *   1) ВСЕ методы — POST (даже информационные)
 *   2) Заголовок: `x-api-key: <API KEY>` (выдаётся в ЛК интегратора)
 *   3) Тело каждого запроса содержит `Token` (JWT из /Authorize) + `CashboxUniqueNumber`
 *   4) Ответ всегда обёрнут: { "Data": { ... } }
 *   5) При ошибке 505 — failover: HTTP-заголовок `AlternativeDomainNames`
 *      содержит список запасных хостов через запятую → повторить на каждом
 *   6) Если касса 72 часа без связи с ОФД → ошибка 18, нужно проверить оплату ОФД
 *
 * Известные endpoint'ы (часть реализована, часть в TODO):
 *   POST /api/v4/Authorize                    — авторизация → токен
 *   POST /api/v4/cashbox/client-info          — состояние кассы, лицензия, ОФД
 *   POST /api/v4/Cashbox/ChangeToken          — смена токена ОФД
 *   POST /api/v4/Cashbox/ShiftHistory         — история смен
 *   POST /api/v4/Check                        — TODO: создание чека (продажа/возврат)
 *   (раздел «Курьеры» — TODO: специальные методы для платформ)
 */

const https = require('https');

class WebkassaClient {
  /**
   * @param {object} cfg
   * @param {string} cfg.baseUrl     - https://devkkm.webkassa.kz (тест) или прод
   * @param {string} cfg.apiKey      - WKD-XXXX-... из ЛК интегратора (заголовок x-api-key)
   * @param {string} cfg.login       - email, которым регистрировались в Webkassa
   * @param {string} cfg.password    - пароль от той же учётки
   * @param {string} cfg.kassaNumber - заводской номер кассы (CashboxUniqueNumber)
   * @param {number} [cfg.tokenTtlMin=55] - сколько минут кэшировать JWT
   * @param {string[]} [cfg.alternativeDomains] - запасные хосты (заполняются автоматически)
   */
  constructor(cfg) {
    if (!cfg.baseUrl) throw new Error('Webkassa: baseUrl обязателен');
    if (!cfg.apiKey) throw new Error('Webkassa: apiKey обязателен');
    if (!cfg.login || !cfg.password) {
      throw new Error('Webkassa: login и password обязательны для /Authorize');
    }
    if (!cfg.kassaNumber) {
      console.warn('[webkassa] kassaNumber не задан — методы Check работать не будут');
    }

    this.baseUrl = cfg.baseUrl.replace(/\/+$/, '');
    this.apiKey = cfg.apiKey;
    this.login = cfg.login;
    this.password = cfg.password;
    this.kassaNumber = cfg.kassaNumber || null;
    this.tokenTtlMs = (cfg.tokenTtlMin || 55) * 60 * 1000;
    this.alternativeDomains = cfg.alternativeDomains || [];

    // Кэш токена авторизации (живёт обычно час)
    this._token = null;
    this._tokenExpiresAt = 0;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Низкоуровневый HTTP-запрос с поддержкой failover на альтернативные домены
  // ───────────────────────────────────────────────────────────────────────────
  async _httpPost(path, body, hostOverride = null) {
    const baseHost = hostOverride || this.baseUrl;
    const url = new URL(baseHost + path);

    return new Promise((resolve, reject) => {
      const data = JSON.stringify(body || {});
      const options = {
        method: 'POST',
        hostname: url.hostname,
        port: url.port || 443,
        path: url.pathname,
        timeout: 15000,
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data),
          'x-api-key': this.apiKey,
          'Accept': 'application/json',
        },
      };

      const req = https.request(options, (res) => {
        let buf = '';
        res.on('data', (c) => (buf += c));
        res.on('end', () => {
          // Failover: парсим AlternativeDomainNames
          const altHeader = res.headers['alternativedomainnames']
                         || res.headers['AlternativeDomainNames'];
          if (altHeader) {
            this.alternativeDomains = String(altHeader)
              .split(',').map((s) => s.trim()).filter(Boolean);
          }

          let parsed;
          try { parsed = JSON.parse(buf); } catch { parsed = { raw: buf }; }

          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: parsed,
          });
        });
      });

      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Webkassa: timeout'));
      });

      req.write(data);
      req.end();
    });
  }

  /**
   * Выполнить запрос с автоматическим failover на альтернативные домены при ошибке 505.
   *
   * ⚠ Webkassa в стиле SOAP/SOAP-like: возвращает HTTP 200 ДАЖЕ ПРИ ОШИБКАХ,
   * а сами ошибки кладёт в body.Errors. Поэтому здесь же проверяем тело.
   */
  async _request(path, body) {
    let response;
    try {
      response = await this._httpPost(path, body);
    } catch (err) {
      for (const altHost of this.alternativeDomains) {
        try {
          response = await this._httpPost(path, body, `https://${altHost}`);
          break;
        } catch {
          continue;
        }
      }
      if (!response) throw err;
    }

    // Failover при 505
    if (response.status === 505 && this.alternativeDomains.length > 0) {
      for (const altHost of this.alternativeDomains) {
        const altResp = await this._httpPost(path, body, `https://${altHost}`);
        if (altResp.status !== 505) {
          response = altResp;
          break;
        }
      }
    }

    // ⚠ КРИТИЧНО: Webkassa-стиль — ошибки в body даже при HTTP 200
    const errors = response.body?.Errors;
    if (Array.isArray(errors) && errors.length > 0) {
      const err = errors[0];
      const e = new Error(
        `Webkassa Error Code ${err.Code}: ${err.Text}`
      );
      e.webkassaCode = err.Code;
      e.webkassaText = err.Text;
      e.path = path;
      throw e;
    }

    return response;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // /api/v4/Authorize — получить токен сессии
  // ───────────────────────────────────────────────────────────────────────────
  // ✅ Подтверждено из Postman docs (Integrators v4 2.0.3):
  //   Body: { Login: <email>, Password: <password> }
  //   Headers: x-api-key: <API KEY>
  //   Response: { Data: { Token: "1a4e7fd2..." } } (hex, не JWT)
  //   Токен в Postman сохраняется в переменную AUTHToken
  async authorize() {
    // Если токен ещё свежий — возвращаем из кэша
    if (this._token && Date.now() < this._tokenExpiresAt) {
      return this._token;
    }

    const resp = await this._request('/api/v4/Authorize', {
      Login: this.login,
      Password: this.password,
    });

    if (resp.status !== 200) {
      throw new Error(
        `Webkassa /Authorize вернул ${resp.status}: ${JSON.stringify(resp.body)}`
      );
    }

    // Структура ответа (предположительно):
    // { "Data": { "Token": "eyJhbGc...", ... } }
    // ТОЧНОЕ имя поля — сверить с Postman docs
    const token = resp.body?.Data?.Token || resp.body?.Token || resp.body?.AccessToken;
    if (!token) {
      throw new Error(
        `Webkassa /Authorize: не нашли токен в ответе. Полный ответ: ${JSON.stringify(resp.body)}`
      );
    }

    this._token = token;
    this._tokenExpiresAt = Date.now() + this.tokenTtlMs;
    return token;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // /api-portal/v4/cashbox/client-info — информация о кассе, лицензии, ОФД
  // ───────────────────────────────────────────────────────────────────────────
  // ✅ Подтверждено из Postman docs.
  // ⚠ URL содержит ПРЕФИКС /api-portal/ (а не просто /api/), это важно!
  async getCashboxInfo() {
    const token = await this.authorize();
    const resp = await this._request('/api-portal/v4/cashbox/client-info', {
      Token: token,
      CashboxUniqueNumber: this.kassaNumber,
    });

    if (resp.status !== 200) {
      throw new Error(
        `Webkassa /cashbox/client-info вернул ${resp.status}: ${JSON.stringify(resp.body)}`
      );
    }

    // Ответ (из скриншота docs):
    // { Data: {
    //     CashboxStatus: 1,        // статус кассы
    //     License: { LicenseStatus: 2, LicenseExpirationDate: "..." },
    //     Ofd: { Ofd: 4, Expiration: "..." },
    //     // также (новое от 30.03.2026): контакты ЦТО, инфо о лицензии
    // }}
    return resp.body?.Data || resp.body;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // /api/v4/Check — фискализация чека (продажа или возврат)
  // TODO: полная структура полей — после получения Postman docs
  // ───────────────────────────────────────────────────────────────────────────
  async createCheck({
    operationType = 2,        // 2 = продажа (приход), 3 = возврат, ТОЧНО уточнить!
    positions,                // массив позиций товаров/услуг
    payments,                 // массив способов оплаты
    customerEmail,
    customerPhone,
    externalCheckNumber,      // ID операции у нас (для идемпотентности)
    roundType,                // тип округления (см. docs от 16.03.2026)
  }) {
    const token = await this.authorize();
    const resp = await this._request('/api/v4/Check', {
      Token: token,
      CashboxUniqueNumber: this.kassaNumber,
      OperationType: operationType,
      Positions: positions,
      Payments: payments,
      CustomerEmail: customerEmail,
      CustomerPhone: customerPhone,
      ExternalCheckNumber: externalCheckNumber,
      RoundType: roundType,
    });

    if (resp.status !== 200) {
      throw new Error(
        `Webkassa /Check вернул ${resp.status}: ${JSON.stringify(resp.body)}`
      );
    }

    return resp.body?.Data || resp.body;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // /api/v4/Check/HistoryByNumber — получить чек по фискальному номеру
  // (Это Сервис #6 Platform API: «Проверка статуса чека»)
  // ───────────────────────────────────────────────────────────────────────────
  // ✅ Подтверждено из Postman docs.
  // ⚠ ВАЖНО: имя поля cashboxUniqueNumber — camelCase (в других методах
  //   встречается CashboxUniqueNumber — PascalCase). API не консистентен.
  async getCheckByNumber({ checkNumber, shiftNumber }) {
    if (!checkNumber) throw new Error('checkNumber обязателен');
    if (!shiftNumber) throw new Error('shiftNumber обязателен');

    const token = await this.authorize();
    const resp = await this._request('/api/v4/Check/HistoryByNumber', {
      Token: token,
      cashboxUniqueNumber: this.kassaNumber,  // camelCase — это специально для этого метода
      Number: parseInt(checkNumber, 10),
      shiftNumber: parseInt(shiftNumber, 10),
    });

    if (resp.status !== 200) {
      throw new Error(
        `Webkassa /Check/HistoryByNumber вернул ${resp.status}: ${JSON.stringify(resp.body)}`
      );
    }

    // Ответ содержит полную информацию о чеке:
    // { Data: {
    //     CashboxUniqueNumber, CashboxRegistrationNumber, CashboxIdentityNumber,
    //     Address, Number, OrderNumber, RegistratedOn, RegistratedOnUTC,
    //     EmployeeName, EmployeeCode, ...позиции, суммы, налоги, статус...
    // }}
    return resp.body?.Data || resp.body;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // /api/v4/Ticket/PrintFormat — печатная форма чека (для принтера/PDF)
  // ───────────────────────────────────────────────────────────────────────────
  // ✅ Подтверждено из Postman docs.
  // Возвращает массив строк (Lines) с типами: 0=text, 1=image(base64), 2=QR.
  // Можем использовать чтобы отдать клиенту-курьерке готовый чек на печать
  // или для генерации PDF.
  //
  // @param {object} opts
  // @param {string} opts.externalCheckNumber - UUID нашего чека (тот же что давали при create)
  // @param {number} [opts.paperKind=3] - 0=80мм, 3=57мм, 12=A4 портрет, 13=A4 ландшафт
  // @param {string} [opts.primaryLang='kk-KZ'] - основной язык чека (kk-KZ, ru-RU, en-US)
  // @param {string} [opts.secondaryLang='ru-RU'] - второй язык (опционально)
  async getCheckPrintFormat({
    externalCheckNumber,
    paperKind = 3,
    primaryLang = 'kk-KZ',
    secondaryLang = 'ru-RU',
  }) {
    if (!externalCheckNumber) throw new Error('externalCheckNumber обязателен');

    const token = await this.authorize();

    // Этот метод требует доп. заголовки Accept-Language + Secondary-Language —
    // делаем POST вручную, чтобы их установить
    const url = new URL(this.baseUrl + '/api/v4/Ticket/PrintFormat');
    const body = {
      Token: token,
      ExternalCheckNumber: externalCheckNumber,
      CashboxUniqueNumber: this.kassaNumber,
      PaperKind: paperKind,
    };

    return new Promise((resolve, reject) => {
      const data = JSON.stringify(body);
      const req = https.request({
        method: 'POST',
        hostname: url.hostname,
        port: 443,
        path: url.pathname,
        timeout: 15000,
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data),
          'x-api-key': this.apiKey,
          'Accept-Language': primaryLang,
          'Secondary-Language': secondaryLang,
        },
      }, (res) => {
        let buf = '';
        res.on('data', (c) => (buf += c));
        res.on('end', () => {
          try {
            const parsed = JSON.parse(buf);
            if (res.statusCode !== 200) {
              return reject(new Error(
                `Webkassa /Ticket/PrintFormat ${res.statusCode}: ${JSON.stringify(parsed)}`
              ));
            }
            // Возвращаем массив строк { Order, Type, Value, Style }
            resolve(parsed?.Data?.Lines || []);
          } catch (e) {
            reject(new Error('parse error: ' + e.message));
          }
        });
      });
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
      req.write(data);
      req.end();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // КУРЬЕРСКАЯ ЭКОНОМИКА — основная фича для нашего клиента (курьерская служба)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Архитектура:
  //   1) Платформа (через нас) загружает предоформленный заказ
  //   2) Курьер видит его в мобильном приложении Webkassa
  //   3) Курьер фискализирует чек при доставке (это делает приложение Webkassa)
  //   4) Webkassa шлёт webhook на наш URL с фискальным номером
  //   5) Мы обновляем у себя статус и возвращаем результат курьерке
  //
  // ВАЖНО: фактическую фискализацию делает Webkassa-приложение курьера.
  // Мы только загружаем заказ и принимаем уведомление. Это и есть платформенная
  // модель из НК 2026.

  /**
   * POST /api/v4/Courier/UploadExternalOrder
   * Загрузить предоформленный заказ для последующей фискализации курьером.
   *
   * @param {object} opts
   * @param {string} opts.orderNumber  - уникальный номер заказа В РАМКАХ ОРГАНИЗАЦИИ
   *                                     (если дублируется — Webkassa вернёт ошибку)
   * @param {Array}  opts.positions    - массив позиций. Каждая:
   *   {
   *     Count: число (обяз) — количество
   *     Price: число (обяз) — цена за единицу
   *     TaxPercent: число (обяз) — налоговая ставка (16 для НДС 2026)
   *     TaxType: 0 (без налога) | 100 (НДС) (обяз)
   *     PositionName: строка (обяз) — наименование
   *     PositionCode: строка (опц)
   *     Discount: число (опц) — скидка в тенге
   *     Markup: число (опц) — наценка в тенге
   *     SectionCode: строка (опц)
   *     UnitCode: число (обяз) — код единицы измерения (796 = штука)
   *   }
   * @param {string} [opts.customerEmail] - если задан, Webkassa отправит чек на email
   * @param {string} [opts.customerPhone]
   *
   * @returns {Promise<{ ok: true }>}
   */
  async uploadCourierOrder({ orderNumber, positions, customerEmail, customerPhone }) {
    if (!orderNumber) throw new Error('orderNumber обязателен');
    if (!Array.isArray(positions) || positions.length === 0) {
      throw new Error('positions обязателен (минимум 1 позиция)');
    }

    const token = await this.authorize();
    // ⚠ Путь БЕЗ /v4/ — это явно показывает curl-пример в Postman docs:
    //   `https://devkkm.webkassa.kz/api/Courier/UploadExternalOrder`
    // Несмотря на то что заголовок метода говорит /api/v4/Courier/...
    // Webkassa API некосистентен, curl-пример — источник истины.
    const resp = await this._request('/api/Courier/UploadExternalOrder', {
      Token: token,
      OrderNumber: orderNumber,
      Positions: positions,
      CustomerEmail: customerEmail || undefined,
      CustomerPhone: customerPhone || undefined,
    });

    if (resp.status !== 200) {
      throw new Error(
        `Webkassa /Courier/UploadExternalOrder вернул ${resp.status}: ${JSON.stringify(resp.body)}`
      );
    }

    // Успешный ответ: { Data: true }
    return { ok: resp.body?.Data === true, raw: resp.body };
  }

  /**
   * Удобная обёртка: создать заказ для выплаты курьеру за доставку.
   * Под капотом вызывает uploadCourierOrder с одной позицией «Доставка».
   *
   * Налоговый момент: курьерская выплата самозанятому в платформенной модели
   * чаще всего идёт БЕЗ НДС (TaxType=0). Для НДС-плательщиков использовать
   * uploadCourierOrder напрямую.
   */
  async uploadCourierPayment({
    orderNumber,
    amount,                       // сумма выплаты курьеру
    serviceName = 'Услуги доставки',
    customerEmail,
    customerPhone,
    withoutVat = true,            // по умолчанию без НДС (самозанятый)
  }) {
    return this.uploadCourierOrder({
      orderNumber,
      customerEmail,
      customerPhone,
      positions: [
        {
          Count: 1,
          Price: parseFloat(amount),
          TaxPercent: withoutVat ? 0 : 16,
          TaxType: withoutVat ? 0 : 100,
          PositionName: serviceName,
          PositionCode: 'DELIVERY',
          Discount: 0,
          Markup: 0,
          SectionCode: '1',
          UnitCode: 796, // 796 = штука (стандартный ОКЕИ)
        },
      ],
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TODO — ещё нужны методы из docs:
  //   POST /api/v4/Cashbox/ChangeToken  — смена токена ОФД
  //   POST /api/v4/Cashbox/ShiftHistory — история смен
  // ───────────────────────────────────────────────────────────────────────────

  /**
   * Smoke-test: проверить что все credentials работают (авторизация + запрос
   * информации о кассе). Возвращает структурированный отчёт.
   */
  async smokeTest() {
    const report = {
      baseUrl: this.baseUrl,
      kassa: this.kassaNumber,
      steps: [],
      ok: true,
    };

    // Шаг 1: авторизация
    try {
      const token = await this.authorize();
      report.steps.push({
        step: 'authorize',
        ok: true,
        tokenPrefix: token.substring(0, 16) + '...',
      });
    } catch (err) {
      report.ok = false;
      report.steps.push({ step: 'authorize', ok: false, error: err.message });
      return report;
    }

    // Шаг 2: получение информации о кассе
    try {
      const info = await this.getCashboxInfo();
      report.steps.push({
        step: 'cashbox_info',
        ok: true,
        cashboxStatus: info?.CashboxStatus,
        licenseStatus: info?.License?.LicenseStatus,
        licenseExpires: info?.License?.LicenseExpirationDate,
        ofdCode: info?.Ofd?.Ofd,
        ofdExpires: info?.Ofd?.Expiration,
      });
    } catch (err) {
      report.ok = false;
      report.steps.push({ step: 'cashbox_info', ok: false, error: err.message });
    }

    return report;
  }
}

/**
 * Создать клиент из env-переменных.
 */
function createWebkassaClient() {
  return new WebkassaClient({
    baseUrl: process.env.WEBKASSA_BASE_URL || 'https://devkkm.webkassa.kz',
    apiKey: process.env.WEBKASSA_API_KEY,
    login: process.env.WEBKASSA_LOGIN,
    password: process.env.WEBKASSA_PASSWORD,
    kassaNumber: process.env.WEBKASSA_KASSA_NUMBER,
    tokenTtlMin: parseInt(process.env.WEBKASSA_TOKEN_TTL_MIN || '55', 10),
  });
}

module.exports = { WebkassaClient, createWebkassaClient };
