# Облачные бэкапы прод-БД Esep

Ежесуточно в 02:00 Алматы workflow [.github/workflows/db-backup.yml](../.github/workflows/db-backup.yml)
снимает `pg_dump` с прод-Postgres (Railway), шифрует AES-256 и кладёт в артефакты
GitHub Actions (хранение 30 дней). Репозиторий публичный — незашифрованный дамп
туда класть НЕЛЬЗЯ.

> Контекст: 2026-07 Railway приостановил аккаунт (закончился план), все сервисы
> вернули 404. Данные тогда уцелели — но если бы Railway удалил, а не приостановил,
> без бэкапа потерялись бы все пользователи и лиды. Отсюда этот workflow.

## Включение (один раз, ~2 минуты)

GitHub → репозиторий `esep` → Settings → Secrets and variables → Actions →
New repository secret:

1. `PROD_DATABASE_URL` — публичный URL прод-Postgres из Railway
   (проект Esep → Postgres → вкладка **Connect** → **Public Network** URL,
   начинается с `postgresql://...proxy.rlwy.net:PORT/railway`).
2. `BACKUP_PASSPHRASE` — придумать длинную фразу и **сохранить в менеджере
   паролей** (без неё бэкапы не расшифровать).

Проверка: Actions → **DB Backup** → **Run workflow** → дождаться зелёного →
в артефактах появится `esep-db-<id>`.

## Восстановление

```bash
# 1. Скачать артефакт из Actions (esep-db-<run_id>), распаковать zip
# 2. Расшифровать:
openssl enc -d -aes-256-cbc -pbkdf2 -in backup.dump.enc -out backup.dump -pass pass:<BACKUP_PASSPHRASE>
# 3. Восстановить (в пустую БД или с --clean на существующую):
pg_restore --no-owner --clean --if-exists -d "$DATABASE_URL" backup.dump
```

## Что внутри

Полный дамп прод-базы: пользователи, тарифы/подписки, счета, транзакции, лиды,
фидбек, налоговые конфиги, Platform API — все таблицы (`server/src/index.js`).

## Связанное

- Тот же механизм для StudyHub: `studyhub/docs/CLOUD-BACKUP.md`.
- ⚠️ Проверь в Railway, что не оформились ДВЕ подписки Hobby (оплата прошла
  дважды 2026-07) — Billing → Subscriptions, лишнюю отменить.
