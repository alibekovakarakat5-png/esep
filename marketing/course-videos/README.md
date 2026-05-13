# Esep Course Videos

Видео-уроки для курса **«НК 2026 за полчаса»** — генерируются программно
через [Remotion](https://www.remotion.dev) + бесплатный TTS.

Один сценарий → 4 продукта:

1. 🎬 **Reel 9:16** — для Instagram/TikTok (30–45 сек, с обрывом-cliffhanger)
2. 📺 **Full 16:9** — для встройки в Esep app (полный урок ~2-3 мин)
3. 📄 **Markdown** — текст урока в приложении и на лендинге
4. 🤖 **Knowledge base** — индексируется в AI-чат Esep

---

## Структура

```
course-videos/
├── package.json
├── remotion.config.ts
├── tsconfig.json
├── src/
│   ├── index.ts           # Remotion entry
│   ├── Root.tsx           # composition registry
│   ├── theme.ts           # бренд-палитра Esep
│   └── lessons/
│       ├── Lesson01Reel.tsx   # 9:16, 4 сцены
│       └── Lesson01Full.tsx   # 16:9, 9 сцен
├── scripts/
│   └── generate-tts.js    # TTS (Edge / ElevenLabs)
├── scenes/
│   └── lesson-01.json     # сценарий + источники
├── content/
│   └── lesson-01-mrp.md   # in-app markdown
├── public/
│   └── audio/             # mp3 от TTS
└── out/                   # отрендеренные видео
```

---

## Production: как отрендерить пилотный урок

### 0. Установить зависимости

```bash
cd marketing/course-videos
npm install
```

### 1. Сгенерировать TTS аудио

**Вариант A — бесплатный Edge TTS (по умолчанию):**

```bash
node scripts/generate-tts.js --lesson=01 --version=reel
node scripts/generate-tts.js --lesson=01 --version=full
```

Голос: `ru-RU-DmitryNeural`, скорость `+15%` (см. `scenes/lesson-01.json`).

**Вариант B — ElevenLabs (платный, для сравнения):**

```bash
$env:ELEVENLABS_API_KEY="sk_..."   # PowerShell
# или: export ELEVENLABS_API_KEY="sk_..."   # bash

node scripts/generate-tts.js --lesson=01 --version=reel --provider=elevenlabs
node scripts/generate-tts.js --lesson=01 --version=full --provider=elevenlabs
```

### 2. Рендер видео

```bash
# Reel (1080×1920, ~30 сек)
npm run render:reel

# Full (1920×1080, ~2 мин)
npm run render:full

# Оба сразу
npm run render:all
```

Результат — в `out/`:
- `lesson-01-reel.mp4` — заливаем в Instagram/TikTok
- `lesson-01-full.mp4` — встраиваем в курс в приложении

### 3. Превью в браузере (для правок)

```bash
npm run studio
```

Откроется Remotion Studio — можно перематывать кадры, проверять анимации.

---

## Дистрибуция

### Instagram Reel
1. Загружаем `lesson-01-reel.mp4` напрямую в Reels
2. Описание: тизер + ссылка `esep.kz/курс`
3. Хештеги: `#нк2026 #ипказахстан #налоги2026 #esepkz`

### In-app (Esep)
- `lesson-01-full.mp4` → загружаем в `app.esepkz.com/static/courses/`
- Контент урока → `content/lesson-01-mrp.md` рендерится в экране урока
- Доступ — только на тарифе `accountant` или `accountant_pro` (бесплатно при подписке)

### Лендинг (SEO)
- `content/lesson-01-mrp.md` → пересобираем в HTML на esepkz.com/blog
- Видео встраивается как `<video>` или YouTube

### AI knowledge base
- Контент маркдауна автоматически попадает в AI-чат через
  `server/src/jobs/ingestPlatformKnowledge.js`
- При запросе пользователя «Сколько МРП в 2026?» — AI цитирует урок
  и ссылается на adilet.zan.kz

---

## Добавить новый урок

1. Создать `scenes/lesson-02.json` (по образцу `lesson-01.json`)
2. Скопировать `Lesson01Reel.tsx` → `Lesson02Reel.tsx`, поправить контент
3. То же для Full
4. Зарегистрировать в `src/Root.tsx`
5. Прогнать TTS + render

Запланированные уроки (см. `../../CLAUDE.md`):

1. ✅ МРП и МЗП 2026 — пилот
2. ⏳ Упрощёнка 910: ставка 4%, лимит сотрудников снят
3. ⏳ НДС 16% и порог 10 000 МРП
4. ⏳ Упрощёнка освобождена от НДС
5. ⏳ ОПВР работодателя 3.5%
6. ⏳ СО за себя 5% и за работников 5%
7. ⏳ ИПН прогрессивный 10/15% + вычет 30 МРП
8. ⏳ СН для ТОО упрощён 6%
9. ⏳ Самозанятые 4% — патент отменён
10. ⏳ Дедлайны 2026 — что когда сдавать

---

## Лицензии / источники

Все факты в скриптах — со ссылками на первоисточники:
- adilet.zan.kz (официальные тексты законов)
- kgd.gov.kz (разъяснения налогового комитета)

В каждом видео — нижний колонтитул с ссылкой на источник.

## Технические детали

- Remotion 4.x, React 18, TypeScript
- TTS: `msedge-tts` (free) или ElevenLabs API
- Output: H.264, CRF 18, 30fps
- Безопасные зоны для Instagram/TikTok соблюдены (см. `src/theme.ts`)

## Проблемы при рендере

- **«Cannot find module 'msedge-tts'»** → `npm install` сначала
- **Edge TTS возвращает ошибку 401** → попробуйте через VPN (бывают региональные блокировки)
- **Чёрный кадр в конце** → длительность в `Root.tsx` больше суммы сцен, это нормально
- **Голос звучит слишком медленно** → крутите `voice.edgeRate` в scenes JSON (макс `+50%`)
