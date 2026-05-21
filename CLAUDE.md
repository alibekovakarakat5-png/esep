# CLAUDE.md — Esep + Connect ecosystem

Чтобы не перечитывать одни и те же файлы. Здесь — карта проектов и где что лежит.

> **Дата актуальности этого файла:** 2026-05-18.
> Свежие разделы внизу — Platform API + Enterprise клиенты (раздел 14).

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

### 🟣 Voxa-video (`c:\Users\USER\Desktop\voxa-video`)
Локальный Remotion-проект для генерации видео (Instagram Reels + 16:9 explainer'ы). Не под git Esep'а.
- **Studio**: `http://localhost:3003` (`npm run studio`)
- **Encoder** (canvas → mp4/webm): `http://localhost:3099` (`node serve-and-encode.mjs`)
- **Композиции**: `src/compositions/esep/Edu*.tsx`
- **TTS**: ElevenLabs (`generate-esep-voice.mjs`) или бесплатный Edge TTS (`generate-edge-voice.mjs` — голос `ru-RU-SvetlanaNeural` +15%)
- **Аудио**: `public/audio/esep/*.mp3`
- **Сценарии**: `public/audio/esep/_scripts_edu.json`, `_scripts_advanced.json`
- **Рендер**: `--sequence` → PNG в `out/<CompositionId>/`, затем encoder делает mp4
- ⚠ Использует Remotion 4.0.194 (старая версия без rspack) — на этой машине Device Guard блокирует rspack/esbuild новых версий

---

## 2. Эталонные KZ-константы 2026 (НК 214-VIII)

| Параметр | Значение |
|---|---|
| МРП | 4 325 ₸ |
| МЗП | 85 000 ₸ |
| Форма 910 ставка | 4% (СН=0% для СНР, маслихат ±50%) |
| Лимит 910 | 600 000 МРП/год (~2.595 млрд ₸) |
| Лимит сотрудников 910 | снят (был 30) |
| Освобождение упрощёнки от НДС | ✅ с 2026, даже выше порога |
| НДС | 16%, порог 10 000 МРП |
| ИПН прогрессивный | 10% до 8500 МРП, 15% свыше |
| Базовый вычет ИПН | 30 МРП/мес (было 14) |
| ОПВР (работодатель) | 3.5% (было 2.5%) |
| ВОСМС работник | 2% (база до 20 МЗП) |
| ВОСМС работодатель | 3% (база до 40 МЗП) |
| СО | 5% (было 3.5%) |
| ОПВ | 10% |
| СН для ТОО | 6% от ФОТ (упрощён, без вычета СО) |
| Самозанятые (СНР) | ИПН = 0%. Платёж 4% — только соцплатежи: ОПВ 1% + ОПВР 1% + СО 1% + ОСМС 1%. Лимит 3600 МРП/год (300 МРП/мес). Источник: gov.kz/КГД |
| Патент | ликвидирован с 01.01.2026 |
| Дивиденды резидентов | 5% ИПН ⚠ ОСВОБОЖДЕНИЕ ЧЕРЕЗ 3 ГОДА — на проверке у бухгалтера |

---

## 3. Esep — карта файлов

```
lib/
├── core/
│   ├── router/app_router.dart          # GoRouter + ShellRoute
│   ├── constants/kz_tax_constants.dart # КОНСТАНТЫ НК 2026, расчёты
│   ├── providers/
│   │   ├── user_mode_provider.dart    # ip / too / accountant
│   │   ├── company_provider.dart      # CompanyInfo + isVatPayer
│   │   ├── invoice_provider.dart
│   │   └── accounting_provider.dart
│   ├── models/
│   │   ├── invoice.dart               # Invoice + InvoiceItem + InvoiceUnit (ОКЕИ)
│   │   ├── diagnosis.dart             # 3.B диагностика "Что изменилось"
│   │   └── tax_profile.dart
│   └── services/
│       ├── auth_service.dart          # register(), login() → API
│       ├── esf_service.dart           # XML-генератор ЭСФ — официальный контейнер ИС ЭСФ v2 (invoiceInfoContainer → invoiceBody CDATA → v2:invoice)
│       ├── pdf_service.dart           # PDF счетов (с НДС 16%)
│       ├── diagnosis_service.dart     # Расчёт дельты 2025 vs 2026 для онбординга
│       ├── base_url_stub.dart         # mobile prod URL
│       └── base_url_web.dart          # web prod URL
├── features/
│   ├── auth/screens/auth_screen.dart
│   ├── mode_select/screens/mode_select_screen.dart
│   ├── dashboard/screens/dashboard_screen.dart   # + _DiagnosisBanner (3.B)
│   ├── diagnosis/screens/                        # 3.B диагностический онбординг
│   │   ├── diagnosis_screen.dart                 # Stepper 5 шагов
│   │   └── diagnosis_report_screen.dart          # Отчёт с дельтой
│   ├── invoices/screens/                         # 2.1 ЭСФ XML с НДС
│   ├── settings/screens/settings_screen.dart     # + Switch "Плательщик НДС"
│   └── ...
└── shared/widgets/main_scaffold.dart  # bottom nav

server/
├── src/
│   ├── index.js                       # Express + CORS + ALLOWED_ORIGINS
│   ├── routes/
│   │   ├── auth.js                    # /register (с phone), /login
│   │   ├── auth-recovery.js           # Telegram bind only
│   │   ├── admin.js                   # ⚠ ВКЛАДКИ: Users, Payments, Фидбек, Курс (черновик), Налоги, Статьи, Промокоды
│   │   ├── feedback.js                # POST /feedback (для бета-тестеров)
│   │   └── ai-chat.js
│   ├── data/
│   │   └── esep_platform_knowledge.js # ⚠ База знаний AI-чата (содержит урок 1 + платформа)
│   └── bot/telegram.js                # /reset, notifyNewUser

esep-landing/
├── index.html                        # ⚠ Раздел НК 2026 СКРЫТ (без пункта в меню, без hero-секшена)
├── robots.txt                        # Allow всем AI-ботам, sitemap link
├── sitemap.xml                       # /nk2026/* удалены, остался blog-* + calculator
├── llms.txt                          # описание бренда для AI-search
├── blog-nalogi-ip-2026.html
├── blog-opvr-2026.html
├── blog-samozanyatye-2026.html
├── calculator.html
├── nk2026/                           # ⚠ ВЕСЬ РАЗДЕЛ noindex, скрыт из навигации
│   ├── _styles.css                   # общий CSS кластера
│   ├── index.html                    # хаб-путеводитель
│   ├── mrp-mzp.html                  # Урок 1
│   ├── uproshenka-910.html           # Урок 2
│   ├── nds-16.html                   # Урок 3
│   ├── nds-osvobozhdenie.html        # Урок 4
│   ├── opvr-3-5.html                 # Урок 5
│   ├── so-5.html                     # Урок 6
│   ├── ipn-progressivnyy.html        # Урок 7
│   ├── sn-too.html                   # Урок 8
│   ├── samozanyatye.html             # Урок 9
│   ├── dedlayny-2026.html            # Урок 10
│   ├── marketpleysy.html             # Эксперт: Kaspi/WB/OZON
│   ├── gph-vs-trudovoy.html          # Эксперт: ГПХ vs трудовой
│   └── dividendy.html                # ⚠ Эксперт: дивиденды 5% — С ДИСКЛЕЙМЕРОМ (ждём Фариду)
└── vercel.json

marketing/course-videos/              # старый скаффолд Remotion (НЕ ИСПОЛЬЗУЕТСЯ — переехали в voxa-video)
samples/esf/                          # фикстуры ЭСФ XML + python-валидатор
test/esf_service_test.dart            # 13 unit-тестов для ЭСФ-генератора
leads-100.csv                         # 165 лидов
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
| `send-greetings.ts` | Приветствие лидам по статусу `new` |
| `send-followup.ts` | Повторное касание `contacted` без ответа |
| `send-promo.ts` | Промо/акции по сегменту тегов |

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

## 9. Курс «НК 2026 за полчаса» (СКРЫТО ДО ПРОВЕРКИ)

Состояние на 2026-05-13: **раздел построен, но скрыт от публики**. Открываем когда:
1. Фарида (бухгалтер-тестер) проверит факты по всем 14 темам
2. Доделаем раздел `/learn` в Flutter app
3. Подготовим рекламную кампанию

### Что есть сейчас

**14 SEO-статей** в `esep-landing/nk2026/`:
- Хаб + 10 базовых уроков (МРП, упрощёнка, НДС, ОПВР, СО, ИПН, СН ТОО, самозанятые, дедлайны)
- 3 экспертные темы (маркетплейсы, ГПХ vs трудовой, дивиденды)
- Каждая статья: Schema.org Article+FAQPage, TL;DR, таблица 2025/2026, примеры, FAQ, sources на adilet.zan.kz
- **Все 14 файлов имеют `<meta name="robots" content="noindex,nofollow">`**
- В `sitemap.xml` нет ни одного URL раздела
- В `index.html` лендинга нет пункта меню и hero-секшена

**Видео в `voxa-video/src/compositions/esep/`** (1080×1920 Reel):
- `EduLessonMRP` — Урок 1 (39 сек) ✅ готов
- `EduMarketplaces` — Маркетплейсы (30 сек) ✅ готов
- `EduGphVsTrudovoy` — ГПХ vs трудовой (31 сек) ✅ готов
- `EduDividends` — Дивиденды 5% (30 сек) ⚠ НЕ ПУБЛИКОВАТЬ до подтверждения

Аудио для всех — Edge TTS бесплатно (`generate-edge-voice.mjs`, голос Svetlana +15%).
PNG-кадры в `out/Esep<Name>/`, encoder на http://localhost:3099 преобразует в mp4/webm.

**PDF-курс**: `esep-landing/nk2026/kurs-nk-2026-chernovik.pdf` (35 страниц) — собран из 10 базовых уроков скриптом `_build_pdf.py` (обложка с дисклеймером + оглавление + уроки с таблицами/примерами/FAQ/источниками). Контент взят как есть из статей — факты НЕ перепроверены.

**Admin (https://api.esepkz.com/api/admin)**: вкладка **📚 Курс (черновик)** — список всех 14 статей с прямыми preview-ссылками + блок «Скачать PDF-курс» (бейдж «черновик, ждёт проверки»).

### Известные факты под вопросом (требуют проверки Фариды)

1. **Дивиденды — освобождение через 3 года владения долей** (статья `dividendy.html`):
   - Норма была в предыдущей редакции НК
   - Точная формулировка в Законе № 214-VIII от 18.07.2025 не подтверждена
   - В статье жёлтый дисклеймер, видео не публикуется
   - Конкретный вопрос Фариде: *«Какая статья НК 2026 регулирует освобождение дивидендов от ИПН? Сохранена ли 3-летняя норма?»*

2. **Все 13 остальных статей** — нужно проверить:
   - Точные ставки, базы, лимиты
   - Номера статей закона в новой нумерации НК 214-VIII
   - Сроки сдачи форм (не изменились ли в 2026)

### План открытия раздела

1. Фарида проверяет факты → создаёт чек-лист из 14 тем
2. Снимаем `<meta name="robots" content="noindex,nofollow">` со всех HTML
3. Возвращаем пункт меню «НК 2026» в `esep-landing/index.html`
4. Возвращаем dark-gradient hero-секшен на главной
5. Добавляем все URL в `sitemap.xml`
6. Запускаем рекламу: Google Ads + Instagram Reels (4 готовых видео)

---

## 10. Что закоммичено за май 2026 (история этапов)

| Коммит | Что |
|---|---|
| `bf38894` | fix(taxes): 5 багов с цифрами 2026 (НДС 12→16% в UI/PDF, СО 3.5→5%, ИПН+СН→ИПН для самозанятых) |
| `5f74a67` | feat(esf): VAT support, buyer IIN, ОКЕИ единицы + pre-export валидация |
| `c80a45b` | fix(esf): вложенный XML-комментарий ломал парсер + harness валидации |
| `700bb85` | fix(admin): чекбокс тестера исчезал (SELECT без is_beta_tester) + вкладка Фидбек |
| `15cc358` | feat(diagnosis): онбординг «Что изменилось для меня» на dashboard |
| `f24a5f0` | feat(course): пилот мини-курса «НК 2026 за полчаса» — урок 1 |
| `31ef407` | feat(seo): NK 2026 топик-хаб + sitemap + robots + llms.txt |
| `073dc25` | feat(seo): полный кластер НК 2026 — все 10 уроков-статей |
| `d206a37` | feat(seo): 3 экспертные статьи (дивиденды, маркетплейсы, ГПХ) |
| `8657c19` | fix(seo): 80% → 30-50% (штраф маркетплейсы), дивиденды скрыты до проверки |
| `0b2dd96` | feat(admin): раздел курсов скрыт от публики, preview только в админке |
| `822ab8a` | docs(claude-md): обновлён до состояния 13.05.2026 |
| `fa3f116` | feat(esf): переход на официальный формат контейнера ИС ЭСФ v2 (модели + UI + тесты + харнесс) |
| `05b3f3c` | fix(taxes): блокеры ТОО-калькулятора — НДС 12→16%, СН 9.5→6%, дивиденды скрыты, ЕСП убран из оптимизатора |
| `4a76071` | feat(course): PDF-курс «НК РК 2026 за полчаса» из 10 уроков + ссылка в админке |
| `4a37251` | docs(claude-md): аудит калькуляторов + PDF-курс, обновлён TODO |
| `868b6da` | fix(landing): устаревшие ставки НДС 12% и СН 9.5% на лендинге |
| `4d1ea26` | fix(taxes): СН для ИП на ОУР (2 МРП/мес) + спецификация формы 910.00 в docs/forms/ |

---

## 11. TODO / Что осталось сделать

### 🔴 Срочно (для продаж)

- [ ] **Фарида проверяет 14 статей НК 2026** — чек-лист готовится отдельно. Особенно дивиденды (статья НК)
- [x] **Получить от Фариды 1С-ЭСФ XML** — получен (`export_esf.xml`), `esf_service.dart` переписан под официальный контейнер ИС ЭСФ v2 (коммит `fa3f116`)
- [ ] **Показать Фариде образец** `samples/esf/esf-vat.xml` — подтвердить, что контейнер принимается импортом esf.gov.kz
- [x] **Аудит калькуляторов перед продажами** — найдены и исправлены блокеры ТОО-калькулятора (НДС 12→16%, СН 9.5→6%, дивиденды завышали итог, ЕСП в оптимизаторе), коммит `05b3f3c`. Лендинг — `868b6da`. СН для ИП на ОУР (2 МРП/мес был пропущен) — `4d1ea26`
- [ ] **Запустить `flutter analyze` и `flutter test`** локально — Device Guard блокирует dart.exe на этой машине. Переписаны тесты ЭСФ; правки калькуляторов и ЭСФ проверены чтением + node/python харнесс + ручная сверка Iconsax/символов, но нужен прогон Dart
- [ ] **Уточнить у Фариды 2 вопроса**: (1) отменён ли режим ЕСП с 2026 — сейчас убран из оптимизатора, но справка осталась; (2) ВОСМС «за себя» — 5% от 1.4 МЗП по НК 2026? — *форма 220.00 подтверждена официальным списком ФНО 2026, вопрос снят*
- [ ] **ИПН с дивидендов** — после подтверждения Фаридой вернуть в ТОО-калькулятор с переключателем «распределяете прибыль?» (сейчас карточка скрыта, `dividendTax` исключён из `totalTax`)
- [ ] **Свериться с Фаридой по СН для ИП на ОУР** — поставили 2 МРП/мес (за себя) + 1 МРП/мес (за работника) по разъяснению КГД; подтвердить точную норму НК

### 🟡 Этап 2 — XML формы для cabinet.salyk.kz

- [ ] **Форма 910 XML** — `form910_service.dart` сейчас генерит выдуманный формат. Разобран официальный пакет СОНО v27 r133: спецификация полей в `docs/forms/form-910-00-v27-spec.md` (реальные имена `field_910_00_001` и т.д.). Осталось: (1) реальный конверт XML-экспорта — образец от пользователя; (2) помесячная модель данных (форма ждёт разбивку `_1.._6`)
- [ ] Форма 200.00 XML (ИПН+СН за сотрудников) — пакет `form_200_00_v33_r142`
- [ ] Форма 300.00 XML (НДС) — для ОУР — пакет `form_300_00_v29_r170`
- [ ] Документ-центр UI в Flutter — единая точка скачивания

### 🟢 Этап 3 — Контент-продукты

- [x] 3.B Диагностика «Что изменилось» — коммит `15cc358`, в проде на dashboard
- [ ] **3.C Раздел `/learn` в Esep app** — встроить уроки + плеер видео. Пока скрыт, открыть позже
- [x] 3.D Wiki по НК 2026 (топик-кластер) — построен, скрыт (см. п.9 этого файла)
- [x] 3.D-PDF PDF-курс из 10 уроков — `kurs-nk-2026-chernovik.pdf`, ссылка в админке (коммит `4a76071`)
- [ ] 3.E Симулятор форм 910/200/300 — не начат

### 🔵 Админка

- [ ] Кнопка «Создать тестера в один клик» (тариф `accountant_pro` + `is_beta_tester=true` одним действием)
- [ ] Просмотр багрепортов с фильтрами и поиском
- [ ] Управление статусом проверки статей курса (готово / на проверке / факты ок)

### ⚪ Видео (когда Фарида подтвердит)

- [ ] Закодировать через `localhost:3099` все 4 готовых ролика → mp4/webm
- [ ] Записать аудио на ElevenLabs (после пополнения квоты) для премиум-голоса в пилотном
- [ ] Сделать ещё 7 экспертных тем: НДС за нерезидента, перенос убытков КПН, корректировка ЭСФ, авансовые платежи КПН, и т.д.

---

## 12. User preferences

- Язык UI / общения: русский
- Коммиты: без эмодзи, ConventionalCommits-стиль (`fix(scope): ...`, `feat(scope): ...`)
- Ответы — концентрированные, без воды
- Email пользователя: aksharayev@gmail.com
- Дата компиляции этой памяти: **2026-05-14**

---

## 13. Запоминай в этом файле!

Всё что часто читаем (структуры, эндпоинты, константы, имена инстансов, ID workspace, статусы фич) — добавлять сюда. Не перечитывать каждый раз `tag.service.ts`, `RAILWAY-DEPLOY.md`, `lead.service.ts` — выжимки лежат тут.

Также обновляй:
- Раздел 10 (история коммитов) — после каждой крупной серии правок
- Раздел 11 (TODO) — отмечать сделанное, добавлять новое
- Раздел 9 (статус курса) — при изменениях в проверке/публикации
- Раздел 14 (Platform API + enterprise клиенты) — добавлять новых клиентов и сервисы

---

## 14. Platform API — enterprise клиенты с кастомным набором сервисов

**Дата создания раздела:** 2026-05-18.

С мая 2026 у Esep появился **новый класс клиентов** — крупные платформы (курьерские службы,
маркетплейсы, агрегаторы), которым нужны не классические бухгалтерские фичи, а
**B2B API-сервисы** для compliance-задач по НК 2026 (платформенная экономика).

Под них в Esep построен отдельный модуль **Platform API** — мульти-тенантный API с
авторизацией по `X-Platform-Key`, feature flags на каждого клиента и подключаемым
набором ОФД-провайдеров.

### 14.1. Архитектура Platform API

```
КЛИЕНТ-ПЛАТФОРМА             ESEP PLATFORM API              ВНЕШНИЕ СИСТЕМЫ
                  HTTPS                          HTTPS
[курьерка/мп] ───────►  /api/platform/*  ──────────►  stat.gov.kz (СНР/ОКЭД)
                          │                            Webkassa (фискализация)
                          │                            КГД ИСНА (реестр, льготы)
                  POST /webhook        ◄──────────  Webkassa (фискализация курьером)
```

- **БД:** Postgres, 4 новые таблицы (`platform_api_keys`, `platform_self_employed_income`,
  `platform_receipts`, `platform_audit_log`) — см. `server/src/services/platform_db.js`
- **Tier:** новый `enterprise` в `server/src/tiers.js` (раньше было только free/solo/
  accountant/accountant_pro)
- **Auth:** middleware `server/src/middleware/platform_api_key.js` — проверяет ключ,
  фичи в `features[]`, месячный лимит запросов, ведёт счётчик
- **Featured flags на ключ:** не все клиенты получают все сервисы — каждому даём
  персональный набор фич в `platform_api_keys.features` JSON

### 14.2. Первый клиент — курьерская служба

**Кейс:** курьерская служба платит курьерам-самозанятым. По НК 2026 (Закон 214-VIII)
платформа выступает налоговым агентом и обязана:
1. Проверять статус курьера (ИП/ФЛ/самозанятый)
2. Фискализировать каждую выплату
3. Следить за лимитом 300 МРП в месяц на каждого курьера
4. Удерживать налог 4% (для самозанятых)

**Без нашего сервиса** клиенту пришлось бы: договор с КГД, договор с ОФД, своя
интеграция, штат compliance. **Через нас** — один API-вызов с одним заголовком.

**Статус сделки:** обсуждение, demo показывается.

### 14.3. 9 сервисов в Platform API

Все доступны по URL префиксу `/api/platform/*`, авторизация `X-Platform-Key: <ключ>`.

| # | Endpoint | Источник данных | Статус | Что делает |
|---|---|---|---|---|
| 1 | `POST /process-payment` | алгоритм + БД + Webkassa | 🟢 **MAGIC** | Один вызов = вся логика (валидация ИИН + ОКЭД + лимит + Webkassa + БД) |
| 2 | `GET /taxpayer/:bin` | stat.gov.kz | 🟢 Live | СНР, ОКЭД, статус ИП/ФЛ/ТОО |
| 3 | `GET /taxpayer/:bin` (тот же) | stat.gov.kz | 🟢 Live | Поле `entity_type.is_ip` |
| 4 | `POST /iin/validate` | алгоритм | 🟢 Live | Валидация ИИН по контрольной цифре (ПП РК № 853) |
| 5 | `POST /cancel-order` | наша БД + Webkassa | 🟢 Live | Soft cancel + откат учёта лимита |
| 6 | (вшито в платёж/webhook) | Webkassa Check/HistoryByNumber | 🟢 Live | Статус фискализации через webhook |
| 7 | `GET /income-limit/*` | наша БД + НК 2026 | 🟢 Live | Лимит 300 МРП в месяц, прогресс-бар |
| 8 | `GET /self-employed/registry` | КГД ИСНА | ⚠ Demo | Заглушка до договора с КГД |
| 9 | `GET /self-employed/benefits/:iin` | КГД ИСНА | ⚠ Demo | Заглушка до договора с КГД |
| + | `POST /webhooks/webkassa-courier` | Webkassa → нам | 🟢 Live | Принимает уведомление о фискализации курьером, обновляет статус чека |

**Магический endpoint `/process-payment`** объединяет шаги 1-7 в один вызов и
возвращает `decision: PROCEED | BLOCK | WARNING`.

### 14.4. Файлы Platform API

```
server/src/
├── tiers.js                              # ← добавлен 'enterprise'
├── middleware/
│   └── platform_api_key.js               # API-key + feature flags + квоты
├── services/
│   ├── iin_algorithm.js                  # валидация ИИН (Постановление № 853)
│   ├── platform_db.js                    # миграции 4 таблиц + helpers
│   ├── taxpayer_lookup.js                # каскад stat.gov.kz + fallback
│   └── webkassa_client.js                # клиент Webkassa Integrators API v4
└── routes/platform/
    ├── index.js                          # главный роутер + /me + описание
    ├── iin_validate.js                   # сервис #4
    ├── taxpayer_info.js                  # сервисы #2, #3
    ├── income_limit.js                   # сервис #7
    ├── process_payment.js                # ← MAGIC сервис #1
    ├── cancel_order.js                   # сервис #5
    └── webhooks.js                       # приём от Webkassa

server/scripts/
├── seed_demo_courier_client.js           # генератор API-ключа для клиента
├── test_platform_e2e.js                  # автоматический e2e (24 проверки)
└── test_webkassa_smoke.js                # smoke против реальной Webkassa

docs/webkassa/
├── api_v4_2.0.3_notes.md                 # выжимка из Postman docs
└── webkassa_docs.html                    # сохранённая копия

server/.env.platform.example              # шаблон env-переменных
```

### 14.5. Webkassa интеграция

ОФД-провайдер для фискализации платформенных выплат.

- **Тип аккаунта:** интегратор (ТОО Ибрагимова К.М, БИН 241040036923)
- **Тестовая среда:** `https://devkkm.webkassa.kz`
- **Касса (тест):** `SWK00035492` (Тестовая касса 18.05.26 16:45)
- **Документация:** Postman Integrators v4-2.0.3 — https://documenter.getpostman.com/view/48749526/2sBXc8o3JF

**Использованные методы:**

| Метод | URL | Назначение |
|---|---|---|
| `POST /api/v4/Authorize` | авторизация | Получить токен (hex, ~32 символа) |
| `POST /api-portal/v4/cashbox/client-info` | информация о кассе | CashboxStatus, лицензия, ОФД |
| `POST /api/Courier/UploadExternalOrder` | загрузка курьерского заказа | ⚠ URL **без /v4/** — это критично |
| `POST /api/v4/Check/HistoryByNumber` | статус чека | Сервис #6 |
| `POST /api/v4/Ticket/PrintFormat` | печатная форма | Для PDF/принтера |

**Архитектура «платформенная экономика»:**

```
1. Курьерка → нам /process-payment
2. Мы → Webkassa /api/Courier/UploadExternalOrder (загружаем заказ)
3. Курьер на телефоне видит заказ в приложении Webkassa
4. Курьер пробивает чек при доставке (Webkassa регистрирует в КГД сама)
5. Webkassa → нам webhook /webhooks/webkassa-courier
6. Мы обновляем status='issued', сохраняем фискальный №
7. Курьерка читает статус через GET /receipts/:order_id
```

**ВАЖНЫЕ нюансы Webkassa API:**

1. **Все методы POST** — даже информационные
2. **HTTP 200 при ошибках** — ошибки в `body.Errors[]`, не в HTTP-статусе.
   Клиент `webkassa_client.js` корректно ловит это в `_request()` и бросает exception.
3. **Casing непостоянен** — где-то `CashboxUniqueNumber` (Pascal), где-то
   `cashboxUniqueNumber` (camel). Сверяться с curl-примером в docs, не с шапкой метода.
4. **Failover** — при коде 505 Webkassa возвращает в HTTP-заголовке
   `AlternativeDomainNames` список запасных хостов через запятую. Клиент это
   парсит и повторяет запрос автоматически.
5. **72 часа автономный режим** — если касса 72ч без связи с ОФД → код 18.
6. **OrderNumber должен быть уникален в рамках организации** — иначе ошибка дубликата.

### 14.6. Известные блокеры (внешние)

| Блокер | Что это | Что делать | Срок |
|---|---|---|---|
| **Webkassa Code 4** | «Пользователь не имеет прав доступа к функционалу Курьеры» | Активировать модуль через ЛК (Кабинет интегратора) или через саппорт | 1-2 дня |
| **Договор с КГД (ИСНА API)** | Для сервисов #8 (реестр), #9 (льготы) | Запрос через клиента-маркетплейса либо через `knpsd@ecc.kz` | 2-4 недели |
| **Webhook URL в Webkassa** | Куда Webkassa шлёт уведомление о фискализации | Настроить в ЛК Webkassa после деплоя на прод. URL: `https://api.esepkz.com/api/platform/webhooks/webkassa-courier` | После деплоя |

### 14.7. Что протестировано

**Локально (на машине разработчика, port 4123, Postgres в Docker):**
- ✅ E2E автотест: 24/24 прохода (`test_platform_e2e.js`)
- ✅ Ручное прокликивание: 18/18 endpoint'ов
- ✅ Webhook от Webkassa симулирован, БД обновляется, ответ `0` возвращается
- ✅ Авторизация Webkassa (реальная) — токен получается
- ✅ Информация о кассе (реальная) — CashboxStatus=1
- ✅ Лимит 300 МРП — корректно блокирует на 6-й выплате по 250к
- ✅ Soft cancel — идемпотентность, защита от чужого order_id
- ✅ Безопасность: 401 без ключа, 403 невалидный ключ, 403 нет фичи

**Не работает в Webkassa (внешний блокер):**
- ❌ `POST /api/Courier/UploadExternalOrder` → Code 4 (нет прав)

### 14.8. Конфигурация env

В `.env` (или Railway переменные):

```
# Обязательные (БД и аутентификация Esep)
DATABASE_URL=postgres://...
JWT_SECRET=<32+ chars>

# Webkassa (для enterprise-клиентов с фискализацией)
WEBKASSA_BASE_URL=https://devkkm.webkassa.kz    # или прод когда выпустят
WEBKASSA_API_KEY=WKD-XXXX-XXXX-XXXX
WEBKASSA_LOGIN=<email>
WEBKASSA_PASSWORD=<password>
WEBKASSA_KASSA_NUMBER=SWK00035492

# Флаг включения реальной фискализации (false = только сохранение в БД)
PLATFORM_FISCALIZATION_ENABLED=false
```

### 14.9. Скрипты для тестирования

```bash
# Локально (Postgres в Docker):
docker run -d --name esep-test-pg -e POSTGRES_PASSWORD=test123 \
  -e POSTGRES_USER=esep -e POSTGRES_DB=esep_test \
  -p 5439:5432 postgres:16-alpine

# Запуск сервера с env (нет dotenv в index.js, передаём inline):
cd server
DATABASE_URL='postgres://esep:test123@localhost:5439/esep_test' \
JWT_SECRET='test_secret_xxxxxxxxxxxxxxxxxxxxxxxxxx' \
PORT=4123 node src/index.js

# Создать тестового enterprise-клиента (получить API-ключ для презентации):
node scripts/seed_demo_courier_client.js

# Прогон полного e2e теста:
node scripts/test_platform_e2e.js

# Smoke реальной Webkassa (после заполнения WEBKASSA_* в env):
node scripts/test_webkassa_smoke.js
```

### 14.10. План на ближайшее

- [ ] Получить от Webkassa активацию курьерского модуля (Code 4)
- [ ] Настроить webhook URL в ЛК Webkassa после деплоя
- [ ] Подготовить Flutter-UI: кастомный дашборд для enterprise клиентов
      (просмотр статуса чеков, лимит курьеров, история операций)
- [ ] Сделать `GET /api/platform/receipts/:order_id` (статус чека для клиента)
- [ ] Письмо в `knpsd@ecc.kz` на ИСНА API (для сервисов #8, #9)
- [ ] Коммерческое предложение (3 этапа: pilot → pre-production → production)
- [ ] Запросить у клиента тестовые данные курьеров для прогона полного потока

### 14.11. Бизнес-логика выбора клиентов

- **Обычные клиенты (free/solo/accountant/accountant_pro)** — пользуются классическим
  Esep: учёт, счета, налоги, ЭСФ, дашборд.
- **Enterprise клиенты** — НЕ используют Flutter-приложение Esep как пользователь.
  Они интегрируют наш Platform API в **свою** систему через REST. Каждому
  enterprise-клиенту даём **кастомный набор фич** (определяется в admin-панели или
  через скрипт `seed_demo_courier_client.js`).

  Тарификация enterprise — индивидуально, не через стандартные тарифы
  free/solo/etc. Биллинг — по `monthly_quota` запросов или per-transaction
  через `platform_audit_log`.
