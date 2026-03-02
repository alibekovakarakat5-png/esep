# 🇰🇿 Есеп — Учёт для ИП Казахстана

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white" alt="PostgreSQL" />
  <img src="https://img.shields.io/badge/Docker-Ready-2496ED?logo=docker&logoColor=white" alt="Docker" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License" />
</p>

**Есеп** — веб-приложение для индивидуальных предпринимателей Казахстана.
Учёт доходов и расходов, выставление счетов, автоматический расчёт налогов по актуальным ставкам РК.

---

## Возможности

| Модуль | Описание |
|--------|----------|
| **Дашборд** | Сводка по доходам, расходам и прибыли за месяц. Прогресс-бар лимита упрощёнки, ближайшие дедлайны |
| **Счета** | Создание, отправка и отслеживание оплаты счетов. Статусы: черновик → отправлен → оплачен / просрочен |
| **Учёт** | Журнал доходов и расходов с разбивкой по контрагентам и источникам |
| **Налоги** | Калькулятор по четырём режимам: ЕСП, Патент, Упрощёнка (910), ОУР. Актуальные МРП и МЗП |
| **Клиенты** | База контрагентов с БИН/ИИН, историей счетов и задолженностью |

---

## Налоговые режимы

```
┌─────────────────────┬──────────┬──────────────────────────┐
│ Режим               │ Ставка   │ Лимит дохода             │
├─────────────────────┼──────────┼──────────────────────────┤
│ ЕСП                 │ 1 МРП/мес│ 1 175 МРП / год          │
│ Патент              │ 1%       │ 3 528 МРП / год          │
│ Упрощёнка (910)     │ 3%       │ 24 038 МРП / полугодие   │
│ ОУР                 │ 10%      │ без лимита               │
└─────────────────────┴──────────┴──────────────────────────┘
МРП 2025 = 3 932 ₸ │ МЗП 2025 = 85 000 ₸
```

---

## Технологии

- **Flutter Web** — кроссплатформенный UI (Material 3)
- **Riverpod** — управление состоянием
- **GoRouter** — навигация
- **Hive** — локальное хранилище (offline-first)
- **fl_chart** — графики и диаграммы
- **pdf / printing** — генерация PDF-счетов
- **PostgreSQL 16** — база данных
- **Nginx** — раздача статики + reverse proxy
- **Docker Compose** — контейнеризация

---

## Быстрый старт

### Требования

- [Flutter SDK](https://docs.flutter.dev/get-started/install) >= 3.3.0
- [Docker](https://docs.docker.com/get-docker/) (для БД)
- Chrome (для web-отладки)

### 1. Клонировать репозиторий

```bash
git clone https://github.com/alibekovakarakat5-png/esep.git
cd esep
```

### 2. Установить зависимости

```bash
flutter pub get
```

### 3. Поднять PostgreSQL

```bash
docker compose -f docker-compose.dev.yml up -d
```

> БД будет доступна на `localhost:5433` (параметры подключения см. в `docker-compose.dev.yml`)

### 4. Запустить приложение

```bash
flutter run -d chrome
```

Приложение откроется в браузере.

---

## Docker (production)

Полный стек: PostgreSQL + Backend + Flutter Web (Nginx)

```bash
cp .env.example .env
# отредактировать .env — задать DB_PASSWORD и JWT_SECRET

docker compose up -d --build
```

Приложение будет доступно на `http://localhost`.

---

## Структура проекта

```
lib/
├── main.dart                        # Точка входа
├── app.dart                         # MaterialApp + Router
├── core/
│   ├── constants/
│   │   └── kz_tax_constants.dart    # МРП, МЗП, ставки, расчёты
│   ├── router/
│   │   └── app_router.dart          # GoRouter маршруты
│   └── theme/
│       └── app_theme.dart           # Тема (KZ sky blue + gold)
├── features/
│   ├── auth/screens/                # Авторизация / Регистрация
│   ├── dashboard/screens/           # Главная — сводка
│   ├── invoices/screens/            # Счета
│   ├── transactions/screens/        # Доходы / Расходы
│   ├── taxes/screens/               # Налоговый калькулятор
│   └── clients/screens/             # Контрагенты
└── shared/
    └── widgets/
        └── main_scaffold.dart       # Bottom navigation
```

---

## Переменные окружения

Скопируйте `.env.example` в `.env` и заполните своими значениями:

```bash
cp .env.example .env
```

| Переменная | Описание |
|------------|----------|
| `DB_PASSWORD` | Пароль PostgreSQL |
| `JWT_SECRET` | Секрет для JWT-токенов (мин. 32 символа) |

---

## Скриншоты

> *Скриншоты будут добавлены после финализации дизайна*

---

## Roadmap

- [ ] Подключение реального backend (Node.js/Express)
- [ ] Авторизация с JWT
- [ ] Импорт выписок Kaspi / Halyk
- [ ] Генерация PDF-счетов
- [ ] Уведомления о дедлайнах
- [ ] Мобильная версия (Android / iOS)
- [ ] Интеграция с eSalyk Azamat

---

## Лицензия

MIT License. Свободное использование для ИП Казахстана.

---

<p align="center">
  Сделано с ❤️ для предпринимателей Казахстана
</p>
