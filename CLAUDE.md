# CLAUDE.md — Esep + Connect ecosystem

Чтобы не перечитывать одни и те же файлы. Здесь — карта проектов и где что лежит.

---

## 1. Два проекта (продаются по отдельности)

### 🟢 Esep (`c:\Users\USER\Desktop\esep`)
Flutter-приложение для ИП и бухгалтеров Казахстана. Считает форму 910, ОПВ, СО, ВОСМС, налоги по новому НК 2026.
- **Фронт**: Flutter (Riverpod + GoRouter + iconsax)
- **Бэк**: Node.js (Express) в `server/` — REST + Telegram bot
- **Лендинг**: `esep-landing/` (HTML/CSS/JS, деплой на Vercel)
- **GitHub**: `alibekovakarakat5-png/esep`
- **Прод**:
  - App: `https://app.esepkz.com` (GitHub Pages)
  - API: `https://api.esepkz.com` (Railway)
  - Landing: `https://esepkz.com` (Vercel)
- **Telegram bot**: `@esep_kz_bot` (password reset через /reset)

### 🟡 Connect (`c:\Users\USER\Desktop\voxa-connect`)
Форк Evolution API. WhatsApp Business REST API + кастомные фишки (CRM, теги, лиды, рассылки, antiban).
- **Бэк**: Node.js + TypeScript + Prisma (Postgres)
- **Multi-tenant**: один сервер — много WA-инстансов
- **Прод**: `https://connect.esepkz.com` (Railway, Postgres + Redis)
- **API key**: см. `voxa-connect/.env` (`AUTHENTICATION_API_KEY`)
- **Локально**: `localhost:9091`, локальный PG: `localhost:5436`
- **Connect dashboard** (наш кастом): `/app/` — login + Inbox + Leads + Tags + Campaigns + Knowledge + Scripts + Schedule + Health + ApiDocs + Settings (React + MUI). Корень `/` редиректит на `/app/`.
- **JSON статус** (для мониторинга): `/api-status`
- **Manager UI** (Evolution v1): `/manager/` — оставлен как fallback

---

## 2. Эталонные KZ-константы 2026 (НК 214-VIII)

| Параметр | Значение |
|---|---|
| МРП | 4 325 ₸ |
| МЗП | 85 000 ₸ |
| Форма 910 ставка | 4% (СН=0% для СНР, маслихат ±50%) |
| Лимит 910 | 600 000 МРП/год (~2.595 млрд ₸) |
| НДС | 16%, порог 10 000 МРП |
| ИПН прогрессивный | 10% до 8500 МРП, 15% свыше |
| Базовый вычет ИПН | 30 МРП/мес |
| ОПВР (работодатель) | 3.5% |
| ВОСМС работник | 2% (база до 20 МЗП) |
| ВОСМС работодатель | 3% (база до 40 МЗП) |
| СО | 5% |
| ОПВ | 10% |
| СН для ТОО | 6% (упрощён) |

---

## 3. Esep — карта файлов

```
lib/
├── core/
│   ├── router/app_router.dart          # GoRouter + ShellRoute
│   ├── providers/
│   │   ├── user_mode_provider.dart    # ip / accountant
│   │   └── accounting_provider.dart
│   ├── models/accounting_client.dart
│   └── services/
│       ├── auth_service.dart          # register(), login() → API
│       ├── base_url_stub.dart         # mobile prod URL
│       └── base_url_web.dart          # web prod URL
├── features/
│   ├── auth/screens/auth_screen.dart  # login/register + phone field
│   ├── mode_select/screens/mode_select_screen.dart
│   ├── settings/screens/settings_screen.dart
│   └── ...
└── shared/widgets/main_scaffold.dart  # bottom nav

server/
├── src/
│   ├── index.js                       # Express + CORS + ALLOWED_ORIGINS
│   ├── routes/
│   │   ├── auth.js                    # /register (с phone), /login
│   │   └── auth-recovery.js           # Telegram bind only (web flow удалён)
│   └── bot/telegram.js                # /reset, notifyNewUser

esep-landing/
├── index.html
├── blog-nalogi-ip-2026.html
├── blog-opvr-2026.html
└── vercel.json

leads-100.csv                          # 165 лидов (147 с телефонами)
B2B-LEADS-ASTANA.md                    # старая выгрузка 44 бухкомпаний
```

---

## 4. Connect — карта кастомных фишек (для продаж)

Внутри Evolution мы добавили:

| Файл | Что делает |
|---|---|
| `src/api/services/lead.service.ts` | CRM лиды (workspace-scoped, статусы: new/contacted/replied/qualified/customer/not_now/unsubscribed/invalid) |
| `src/api/services/tag.service.ts` | Теги контактов + auto-tag правила (new_customer, purchased, vip, no_response, keyword) |
| `src/api/services/broadcast.service.ts` | Массовые рассылки с антибан-очередью |
| `src/api/services/campaign.service.ts` | Маркетинговые кампании |
| `src/api/services/template.service.ts` | Шаблоны сообщений с переменными |
| `src/api/services/inbox.service.ts` | Универсальный inbox (мульти-инстансы) |
| `src/api/services/script.service.ts` | Скрипты продаж (готовые ответы) |
| `src/api/services/knowledge.service.ts` | База знаний для AI-бота |
| `src/api/services/flow-engine.service.ts` | Визуальные flow (drag&drop) |
| `src/api/services/ecommerce.service.ts` | Товары/заказы/корзины |
| `src/api/services/billing.service.ts` | Биллинг для SaaS-режима |
| `src/api/services/schedule.service.ts` | Отложенные сообщения |
| `src/api/services/miniapp.service.ts` | Mini-app внутри WA |
| `src/api/services/proxy.service.ts` | Прокси для инстансов |
| `src/api/services/monitor.service.ts` | Мониторинг здоровья инстансов |
| `src/api/services/antiban/` | Антибан: warmup, rate-limit, typing simulation, slowdown |

**Эндпойнты роутеров** (`src/api/routes/`):
- `lead.router.ts` — `GET/POST/PUT/DELETE /leads/:workspaceSlug` (+ `/stats`, `/:id/status`)
- `crm.router.ts` — теги: `/tags/:instance/contact/:remoteJid/:tagId`
- `business.router.ts`, `campaign.router.ts`, `ecommerce.router.ts`, `knowledge.router.ts`
- `template.router.ts`, `script.router.ts`, `schedule.router.ts`, `call.router.ts`
- `miniapp/`, `proxy.router.ts`, `label.router.ts`

**Dashboard frontend** (`dashboard/`):
- React 19 + MUI 9 + react-router-dom 7 + i18next (RU/EN/KZ)
- Pages: `LoginPage`, `InstancesPage`, `InboxPage`, `LeadsPage` + detail, `ScriptsPage`, `CampaignsPage` + Wizard + Detail, `KnowledgePage`, `MessengerPage`, `ContactsPage`, `TagsPage`, `StatisticsPage`, `SchedulePage`, `HealthPage`, `WebhooksPage`, `ApiDocsPage`, `SettingsPage`, `OnboardingWizard`
- Логин: email+password (JWT) ИЛИ apikey-режим
- Vite `base: /app/` в production, `BrowserRouter basename={import.meta.env.BASE_URL}`
- API URL: same-origin в prod, `localhost:9091` в dev
- Build: `cd dashboard && NODE_ENV=production npm run build` → `dashboard/dist/`
- Сервится через `DashboardRouter` (`src/api/routes/dashboard.router.ts`) под `/app/*`

**Antiban (важно для продаж!)** — defaults в `antiban.config.ts`:
- 12 msg/min, 300/hour, 80 unique recipients/hour
- Warmup: 14 дней, начинает с 15% лимитов
- Typing simulation, online presence, auto-slowdown при rate-limit от WA

---

## 5. Скрипты в `voxa-connect/scripts/`

| Файл | Назначение |
|---|---|
| `import-leads-csv.ts` | Импорт CSV → workspace.lead (универсальный) |
| `import-esep-leads.ts` | Импорт `B2B-LEADS-ASTANA.md` (44 бухкомпании, разовый) |
| `match-leads-contacts.ts` | Сопоставление leads с WA контактами |
| `send-test.ts` | Отправка тестового UTF-8 сообщения |
| `seed-esep-knowledge.ts` | Загрузка базы знаний для AI |
| `seed-esep-scripts.ts` | Загрузка скриптов продаж |
| `send-greetings.ts` | (НОВЫЙ) Приветствие лидам по статусу `new` |
| `send-followup.ts` | (НОВЫЙ) Повторное касание `contacted` без ответа |
| `send-promo.ts` | (НОВЫЙ) Промо/акции по сегменту тегов |

Запуск:
```bash
cd voxa-connect
DATABASE_PROVIDER=postgresql DATABASE_CONNECTION_URI="<pg_url>" \
  npx tsx scripts/<name>.ts
```

---

## 6. Workspace в Connect

- Slug: `esep`
- ID: `cmoifvtic0002qihotukalx7u` (локально)
- Внутри: 165 лидов (147 с телефонами) после `import-leads-csv.ts`

Для прода (Railway) — тот же скрипт с `DATABASE_CONNECTION_URI=${{Postgres.DATABASE_URL}}`.

---

## 7. WhatsApp инстансы

| Имя | Роль |
|---|---|
| `мои` | Личный (тестовый, отправка с 77075884651) |
| `esep-sales-1` | Основной outreach |
| `esep-sales-2` | Прогрев нового номера для холодных |
| `esep-support` | Поддержка действующих клиентов |

---

## 8. Безопасный outreach (правила, чтобы не банили)

| Период | Макс/день | Темп |
|---|---|---|
| День 1-3 | 20 | Только знакомым |
| День 4-7 | 50 | Старые клиенты |
| Неделя 2 | 200 | Очень персонализировано |
| Неделя 3 | 500 | Шаблоны с вариациями |
| Неделя 4+ | 1000+ | Массово с задержками |

- Между сообщениями: **30-90 сек рандом**
- Текст: **варьировать на 30-50%**
- Имя клиента в начале — обязательно
- Не больше 5 одинаковых ссылок подряд

---

## 9. User preferences

- Язык UI / общения: русский
- Коммиты: без эмодзи
- Ответы — концентрированные, без воды
- Email пользователя: aksharayev@gmail.com
- Дата компиляции этой памяти: 2026-05-04

---

## 10. Запоминай в этом файле!

Всё что часто читаем (структуры, эндпоинты, константы, имена инстансов, ID workspace) — добавлять сюда. Не перечитывать каждый раз `tag.service.ts`, `RAILWAY-DEPLOY.md`, `lead.service.ts` — выжимки лежат тут.
