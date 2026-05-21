# Esep Platform API — документация для интеграции

Версия: 1.0
Базовый URL: `https://api.esepkz.com/api/platform`

API для платформ (курьерские службы, маркетплейсы, агрегаторы) —
закрывает обязанности налогового агента по НК РК 2026.

---

## Аутентификация

Все запросы (кроме `GET /` и webhook) требуют заголовок:

```
X-Platform-Key: <ваш ключ>
```

Ключ выдаёт менеджер Esep при подключении. У каждого клиента — свой ключ
с индивидуальным набором сервисов (features) и месячным лимитом запросов.

Коды ответов аутентификации:
- `401` — заголовок X-Platform-Key отсутствует
- `403` — ключ неверный, деактивирован, или сервис не входит в ваш тариф
- `429` — превышен месячный лимит запросов

---

## Быстрый старт

Главное, что нужно знать: **на каждую выплату курьеру вызывайте один
endpoint** — `POST /process-payment`. Он сам делает все проверки.

```bash
curl -X POST https://api.esepkz.com/api/platform/process-payment \
  -H "X-Platform-Key: ВАШ_КЛЮЧ" \
  -H "Content-Type: application/json" \
  -d '{
    "courier_iin": "850101100012",
    "amount": 50000,
    "order_id": "ORD-2026-05-21-001"
  }'
```

Ответ — единое решение:

```json
{
  "ok": true,
  "decision": "PROCEED",
  "iin_valid": true,
  "income_limit": { "would_be_total": 50000, "limit": 1297500, ... },
  "fiscal_status": "awaiting_courier_fiscalization"
}
```

По полю `decision` ваша система решает что делать:
- `PROCEED` — выплату можно проводить
- `WARNING` — можно, но есть нюанс (см. `warnings[]`)
- `BLOCK` — нельзя (см. `errors[]`), например превышен лимит 300 МРП

---

## Сервисы

### 1. POST /process-payment — обработка выплаты (главный)

Объединяет валидацию ИИН, проверку налогоплательщика, контроль лимита
300 МРП, запись операции и постановку чека на фискализацию.

**Тело запроса:**

| Поле | Тип | Обяз. | Описание |
|---|---|---|---|
| `courier_iin` | string | да | ИИН курьера (12 цифр) |
| `amount` | number | да | Сумма выплаты в тенге |
| `order_id` | string | да | Уникальный ID заказа в вашей системе |
| `payment_method` | string | нет | `card` / `wallet` / `cash` |
| `skip_taxpayer_check` | bool | нет | Пропустить проверку через stat.gov.kz (быстрее) |

**Ответ:** `decision`, `iin_valid`, `taxpayer`, `income_limit`,
`fiscal_status`, `warnings[]`, `errors[]`, `processed_in_ms`.

---

### 2-3. GET /taxpayer/:bin — проверка налогоплательщика

Проверка СНР, ОКЭД и статуса (ИП / ФЛ / ТОО) по БИН или ИИН.

```bash
curl https://api.esepkz.com/api/platform/taxpayer/850101100012 \
  -H "X-Platform-Key: ВАШ_КЛЮЧ"
```

**Ответ:** `entity_type` (kind, is_ip), `name`, `oked`, `found_in_registry`.

---

### 4. POST /iin/validate — валидация ИИН

Алгоритмическая проверка контрольной цифры (Постановление № 853).
Мгновенно, без обращения к сети.

```bash
curl -X POST https://api.esepkz.com/api/platform/iin/validate \
  -H "X-Platform-Key: ВАШ_КЛЮЧ" -H "Content-Type: application/json" \
  -d '{"iin": "850101100012"}'
```

**Ответ:** `valid` (bool), `reason`, `details` (дата рождения, пол, век).

---

### 5. POST /cancel-order — отмена заказа

Отмена заказа до фактической фискализации курьером.

**Тело:** `{ "order_id": "...", "reason": "..." }`

Если чек ещё не пробит — soft cancel, откат учёта лимита.
Если уже фискализирован — `409`, нужен возвратный чек.

---

### 6. GET /receipts — статус фискальных чеков

**Один чек:**
```bash
curl https://api.esepkz.com/api/platform/receipts/ORD-2026-05-21-001 \
  -H "X-Platform-Key: ВАШ_КЛЮЧ"
```

**Ответ:**
```json
{
  "order_id": "ORD-2026-05-21-001",
  "status": "issued",
  "status_label": "Фискализирован — чек пробит курьером...",
  "is_fiscalized": true,
  "fiscal": {
    "fiscal_number": "600277054321",
    "qr_url": "https://consumer.oofd.kz/?i=600277054321",
    "fiscalized_at": "21.05.2026 16:05",
    "employee_name": "Курьер Алмат",
    "shift_number": 7
  }
}
```

**Список чеков:** `GET /receipts?status=issued&iin=...&limit=50&offset=0`
— возвращает `total`, `summary` (сводка по статусам), `receipts[]`.

Статусы чека:
- `pending_ofd_contract` — в очереди
- `awaiting_courier_fiscalization` — загружен в Webkassa, ждёт курьера
- `issued` — фискализирован, чек в КГД
- `cancelled` — отменён
- `upload_failed` — ошибка загрузки

---

### 7. GET/POST /income-limit — контроль лимита 300 МРП

По НК 2026 самозанятый не может заработать больше 300 МРП
(1 297 500 ₸) в календарный месяц.

- `GET /income-limit/status/:iin` — текущий остаток лимита
- `GET /income-limit/check?iin=&proposed_amount=` — можно ли начислить
- `POST /income-limit/record` — записать выплату (если не через /process-payment)

---

### 8-9. Реестр и льготы самозанятых (в разработке)

- `GET /self-employed/registry` — реестр самозанятых от КГД
- `GET /self-employed/benefits/:iin` — льготные категории

Сейчас в demo-режиме (поле `mode: "demo"`). Реальные данные —
после подключения к API ИСНА КГД (оформляется).

---

## Webhook — уведомления о фискализации

Когда курьер пробивает чек через мобильное приложение Webkassa,
система присылает нам уведомление, и мы обновляем статус чека.
Вы получаете итог через `GET /receipts/:order_id`.

Webhook-приём настроен на нашей стороне:
`POST /api/platform/webhooks/webkassa-courier`

---

## Архитектура интеграции

```
ВАША СИСТЕМА                ESEP PLATFORM API           ВНЕШНИЕ
                  X-Platform-Key
[выплата] ──────────────►  /process-payment  ──────►  stat.gov.kz
                              │                        Webkassa
                              │                        КГД ИСНА
[статус]  ──────────────►  /receipts/:id
```

Вы интегрируетесь **только с нашим API**. Все договоры с КГД и
операторами фискальных данных — на стороне Esep.

---

## Тестовая среда

Перед production — тестовая среда (sandbox) с тестовыми ИИН и
имитацией ответов КГД/Webkassa. Выдаётся в день подписания договора.

## Поддержка

- WhatsApp / телефон: +7 705 991 47 89
- Сайт: https://business.esepkz.com
