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
| Самозанятые | 4% (1% ИПН + 2% ОПВ + 1% ВОСМС/СО), лимит 3600 МРП/год |
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
