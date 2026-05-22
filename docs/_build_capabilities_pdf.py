# -*- coding: utf-8 -*-
"""Генерация PDF: «Esep для среднего и крупного бизнеса — каталог возможностей».

Клиент-ориентированный документ: только рабочие фичи, как ими пользоваться,
как интегрировать и насколько это сложно.

Запуск:  python docs/_build_capabilities_pdf.py
Результат: Esep-Platform-API-Capabilities.pdf в корне проекта.
"""
import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle,
    HRFlowable,
)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
OUT = os.path.join(ROOT, 'Esep-Platform-API-Capabilities.pdf')

FONT_DIR = r"C:\Windows\Fonts"
pdfmetrics.registerFont(TTFont("DOC", os.path.join(FONT_DIR, "arial.ttf")))
pdfmetrics.registerFont(TTFont("DOC-B", os.path.join(FONT_DIR, "arialbd.ttf")))
pdfmetrics.registerFont(TTFont("DOC-I", os.path.join(FONT_DIR, "ariali.ttf")))
pdfmetrics.registerFontFamily("DOC", normal="DOC", bold="DOC-B", italic="DOC-I")

NAVY   = colors.HexColor("#0F2B46")
TEAL   = colors.HexColor("#0EA5E9")
GREY   = colors.HexColor("#64748B")
LIGHT  = colors.HexColor("#F1F5F9")
BORDER = colors.HexColor("#CBD5E1")
GREEN  = colors.HexColor("#16A34A")
ORANGE = colors.HexColor("#F59E0B")

styles = getSampleStyleSheet()

def S(name, **kw):
    base = kw.pop("parent", styles["Normal"])
    kw.setdefault("fontName", "DOC")
    return ParagraphStyle(name, parent=base, **kw)

ST = {
    "cover_title": S("cover_title", fontName="DOC-B", fontSize=30, leading=36,
                     textColor=NAVY, alignment=TA_CENTER, spaceAfter=10),
    "cover_sub": S("cover_sub", fontSize=13, leading=19, textColor=GREY,
                   alignment=TA_CENTER, spaceAfter=6),
    "cover_acc": S("cover_acc", fontSize=11, leading=15, textColor=TEAL,
                   alignment=TA_CENTER, spaceAfter=4),
    "h1": S("h1", fontName="DOC-B", fontSize=19, leading=24, textColor=NAVY,
            spaceBefore=8, spaceAfter=6),
    "h2": S("h2", fontName="DOC-B", fontSize=13.5, leading=18, textColor=NAVY,
            spaceBefore=12, spaceAfter=4),
    "h3": S("h3", fontName="DOC-B", fontSize=10.5, leading=14, textColor=TEAL,
            spaceBefore=7, spaceAfter=2),
    "body": S("body", fontSize=10, leading=14.5, textColor=colors.black,
              alignment=TA_LEFT, spaceAfter=4),
    "small": S("small", fontSize=9, leading=12, textColor=GREY),
    "code": S("code", fontName="Courier", fontSize=8.3, leading=11,
              textColor=colors.HexColor("#334155"), backColor=LIGHT,
              borderColor=BORDER, borderWidth=0.5, borderPadding=5,
              spaceBefore=2, spaceAfter=4),
    "li": S("li", fontSize=10, leading=14, leftIndent=13, bulletIndent=5,
            spaceAfter=2),
}

def hr():
    return HRFlowable(width="100%", thickness=0.5, color=BORDER,
                      spaceBefore=3, spaceAfter=7)

def diff(level):
    """Бейдж сложности интеграции."""
    cfg = {
        "easy":   (GREEN,  "Очень просто", "★☆☆"),
        "ok":     (TEAL,   "Просто",        "★★☆"),
        "mid":    (ORANGE, "Средне",        "★★★"),
    }[level]
    return (f'<font color="{cfg[0].hexval()}"><b>{cfg[2]}&nbsp;&nbsp;'
            f'{cfg[1]}</b></font>')

def bullets(items):
    return [Paragraph(f"• {x}", ST["li"]) for x in items]

doc = SimpleDocTemplate(
    OUT, pagesize=A4,
    leftMargin=18*mm, rightMargin=18*mm,
    topMargin=17*mm, bottomMargin=15*mm,
    title="Esep для бизнеса — каталог возможностей Platform API",
    author="Esep",
)
story = []

# ─────────────────────────────────────── Обложка ───────────────────────────
story.append(Spacer(1, 45*mm))
story.append(Paragraph("Esep для среднего и крупного бизнеса", ST["cover_title"]))
story.append(Paragraph("Platform API — каталог возможностей", ST["cover_sub"]))
story.append(Spacer(1, 24*mm))
story.append(Paragraph("Compliance по Налоговому кодексу РК 2026", ST["cover_sub"]))
story.append(Paragraph("для платформ: курьерские службы, такси, доставка, "
                       "маркетплейсы, сервисы услуг", ST["cover_sub"]))
story.append(Spacer(1, 40*mm))
story.append(Paragraph("Только реально работающие сервисы", ST["cover_acc"]))
story.append(Paragraph("business.esepkz.com  ·  +7 705 991 47 89", ST["cover_acc"]))
story.append(PageBreak())

# ─────────────────────────────────── 1. Для кого ───────────────────────────
story.append(Paragraph("1. Для кого этот документ", ST["h1"]))
story.append(hr())
story.append(Paragraph(
    "Документ — для платформ, которые выплачивают деньги многим "
    "исполнителям-физлицам: курьерским службам, такси-агрегаторам, сервисам "
    "доставки, маркетплейсам и платформам услуг. По Налоговому кодексу РК "
    "2026 такая платформа — налоговый агент, и обязана правильно оформлять "
    "каждую выплату.", ST["body"]))
story.append(Paragraph(
    "Esep Platform API закрывает эту обязанность. Здесь описана каждая "
    "<b>реально работающая</b> функция: что делает, когда применять, как "
    "вызвать и насколько сложно интегрировать.", ST["body"]))

story.append(Paragraph("Что внутри", ST["h3"]))
for p in bullets([
    "6 рабочих сервисов + встроенная фискализация — раздел 4",
    "Кабинет для вашего финотдела — раздел 5",
    "Пошаговая интеграция и оценка сложности — раздел 6",
    "Безопасность и авторизация — раздел 7",
    "Что в разработке — честно, раздел 8",
]):
    story.append(p)

# ─────────────────────────────── 2. Зачем это нужно ────────────────────────
story.append(Paragraph("2. Зачем это нужно — НК РК 2026", ST["h1"]))
story.append(hr())
story.append(Paragraph(
    "С 2026 года оператор интернет-платформы, который платит исполнителям, "
    "признаётся <b>налоговым агентом</b>. Платформа обязана:", ST["body"]))
for p in bullets([
    "проверять статус исполнителя (ИП / самозанятый / ФЛ);",
    "удерживать социальные платежи с каждой выплаты;",
    "фискализировать каждую выплату с регистрацией в КГД;",
    "следить за лимитом дохода 300 МРП в месяц на исполнителя;",
    "вести учёт и хранить историю для проверок КГД.",
]):
    story.append(p)
story.append(Spacer(1, 4))
story.append(Paragraph(
    "<b>Без Esep</b> платформе пришлось бы заключать договор с КГД, договор "
    "с оператором фискальных данных, разрабатывать интеграцию и держать штат "
    "compliance. <b>С Esep</b> — один HTTP-запрос на каждую выплату. Все "
    "договоры с КГД и операторами фискальных данных — на нашей стороне.",
    ST["body"]))

# ─────────────────────────────── 3. Как устроено ───────────────────────────
story.append(Paragraph("3. Как это устроено", ST["h1"]))
story.append(hr())
story.append(Paragraph(
    "Platform API — это REST API. Ваша система обращается к нам обычными "
    "HTTPS-запросами с одним заголовком авторизации. Никакого SDK ставить "
    "не нужно.", ST["body"]))

arch = ("ВАША СИСТЕМА            ESEP PLATFORM API           ВНЕШНИЕ СИСТЕМЫ<br/>"
        "&nbsp;<br/>"
        "[выплата] --X-Platform-Key--&gt;  /process-payment  --&gt;  stat.gov.kz<br/>"
        "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"
        "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"
        "&nbsp;&nbsp;&nbsp;&nbsp;|&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"
        "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"
        "&nbsp;&nbsp;Webkassa (ОФД)<br/>"
        "[статус]&nbsp;&nbsp;----------------&gt;  /receipts/:id&nbsp;&nbsp;&nbsp;"
        "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;КГД")
story.append(Paragraph(arch, ST["code"]))
story.append(Paragraph(
    "<b>Важно: мы — не платёжный процессинг.</b> Деньги исполнителю платформа "
    "переводит сама, через свой банк. Esep проверяет, оформляет фискальный "
    "чек и ведёт учёт — деньги через нас не идут.", ST["body"]))

story.append(Paragraph("Принципы", ST["h3"]))
for p in bullets([
    "<b>Один заголовок</b> X-Platform-Key — ваш API-ключ.",
    "<b>Набор сервисов под вас</b> — каждому клиенту включаем нужные функции.",
    "<b>Один главный вызов</b> /process-payment делает все проверки сразу.",
    "<b>Аудит каждого запроса</b> — журнал для проверок КГД.",
]):
    story.append(p)

# ─────────────────────────── 4. Рабочие сервисы ────────────────────────────
story.append(PageBreak())
story.append(Paragraph("4. Рабочие сервисы — подробно", ST["h1"]))
story.append(hr())
story.append(Paragraph(
    "Ниже — каждая функция, которая работает прямо сейчас. Для каждой: что "
    "делает, когда применять, как вызвать и сложность интеграции.", ST["body"]))

def feature(num, title, level, endpoint, what, when, example, returns):
    story.append(Paragraph(f"4.{num}&nbsp;&nbsp;{title}", ST["h2"]))
    story.append(Paragraph(
        f'<font name="Courier" size="8.5">{endpoint}</font>'
        f'&nbsp;&nbsp;&nbsp;{diff(level)}', ST["body"]))
    story.append(Paragraph(f"<b>Что делает.</b> {what}", ST["body"]))
    story.append(Paragraph(f"<b>Когда использовать.</b> {when}", ST["body"]))
    story.append(Paragraph("<b>Пример вызова:</b>", ST["body"]))
    story.append(Paragraph(example.replace("\n", "<br/>"), ST["code"]))
    story.append(Paragraph(f"<b>В ответе.</b> {returns}", ST["body"]))

feature(
    1, "Выплата курьеру — главный сервис", "ok",
    "POST /api/platform/process-payment",
    "Один вызов на каждую выплату. Внутри последовательно: валидация ИИН, "
    "проверка статуса исполнителя, контроль лимита 300 МРП, запись операции "
    "в учёт и постановка чека на фискализацию. Возвращает единое решение.",
    "Перед каждой выплатой курьеру или водителю. Это сервис, вокруг которого "
    "строится вся интеграция — остальные нужны точечно.",
    'curl -X POST https://api.esepkz.com/api/platform/process-payment \\\n'
    '  -H "X-Platform-Key: ВАШ_КЛЮЧ" \\\n'
    '  -H "Content-Type: application/json" \\\n'
    '  -d \'{"courier_iin":"850101100012","amount":50000,\n'
    '       "order_id":"ORD-2026-05-22-001"}\'',
    "Поле <b>decision</b> = PROCEED (платить можно) / WARNING (можно, но есть "
    "нюанс) / BLOCK (нельзя). Плюс iin_valid, income_limit (использовано и "
    "остаток), fiscal_status, warnings[], errors[]. Ваша система действует "
    "по одному полю decision.")

feature(
    2, "Валидация ИИН", "easy",
    "POST /api/platform/iin/validate",
    "Математическая проверка ИИН по контрольной цифре (Постановление "
    "Правительства РК № 853). Мгновенно, без обращения к сети.",
    "При вводе ИИН в форму регистрации исполнителя — поймать опечатку до "
    "того, как обращаться в реестры.",
    'curl -X POST https://api.esepkz.com/api/platform/iin/validate \\\n'
    '  -H "X-Platform-Key: ВАШ_КЛЮЧ" \\\n'
    '  -H "Content-Type: application/json" \\\n'
    '  -d \'{"iin":"850101100012"}\'',
    "valid (да/нет), reason (причина отказа), details — дата рождения, пол, "
    "век. Опечатку в ИИН видно сразу.")

feature(
    3, "Проверка налогоплательщика — СНР, ОКЭД, статус ИП / ФЛ / ТОО", "easy",
    "GET /api/platform/taxpayer/:bin",
    "По БИН или ИИН возвращает вид деятельности (ОКЭД), наименование и тип "
    "лица: ИП / самозанятый / ФЛ / ТОО. Источник — открытый реестр Бюро "
    "национальной статистики; если реестр недоступен, тип выводится из "
    "структуры самого БИН.",
    "При регистрации нового исполнителя — убедиться, что он ИП или "
    "самозанятый, а не ТОО (платформе нельзя оформлять выплату на ТОО как "
    "на курьера).",
    'curl https://api.esepkz.com/api/platform/taxpayer/850101100012 \\\n'
    '  -H "X-Platform-Key: ВАШ_КЛЮЧ"',
    "entity_type (тип лица, признак is_ip), name, oked, found_in_registry.")

feature(
    4, "Контроль лимита 300 МРП в месяц", "easy",
    "GET / POST /api/platform/income-limit/*",
    "По НК 2026 самозанятый не может заработать больше 300 МРП "
    "(1 297 500 ₸) в календарный месяц. Мы храним все выплаты через наш API "
    "и считаем нарастающим итогом по каждому исполнителю.",
    "Когда нужно узнать «сколько ещё можно выплатить этому курьеру в этом "
    "месяце» или заранее проверить конкретную сумму.",
    'curl https://api.esepkz.com/api/platform/income-limit/status/850101100012 \\\n'
    '  -H "X-Platform-Key: ВАШ_КЛЮЧ"\n'
    '# либо проверка суммы заранее:\n'
    '# GET /income-limit/check?iin=...&proposed_amount=50000',
    "used (использовано в этом месяце), remaining (остаток), percent. "
    "При превышении исполнитель обязан перейти в ИП.")

feature(
    5, "Аннулирование заказа", "easy",
    "POST /api/platform/cancel-order",
    "Помечает заказ отменённым и откатывает учёт лимита 300 МРП. Работает, "
    "пока чек ещё не фискализирован. Если чек уже пробит — возврат "
    "оформляется возвратным чеком (отдельная процедура).",
    "Курьер отказался или клиент отменил заказ до того, как чек пробит.",
    'curl -X POST https://api.esepkz.com/api/platform/cancel-order \\\n'
    '  -H "X-Platform-Key: ВАШ_КЛЮЧ" \\\n'
    '  -H "Content-Type: application/json" \\\n'
    '  -d \'{"order_id":"ORD-2026-05-22-001","reason":"Курьер отказался"}\'',
    "ok, new_status. Повторный вызов безопасен — операция идемпотентна.")

feature(
    6, "Статус фискального чека", "easy",
    "GET /api/platform/receipts/:order_id",
    "Возвращает текущий статус чека: в очереди / ожидает фискализации / "
    "фискализирован / отменён. Если фискализирован — содержит фискальный "
    "номер и ссылку на QR-код от КГД.",
    "После доставки — проверить, пробит ли чек. Также есть список с "
    "фильтрами: GET /receipts?status=issued&iin=...",
    'curl https://api.esepkz.com/api/platform/receipts/ORD-2026-05-22-001 \\\n'
    '  -H "X-Platform-Key: ВАШ_КЛЮЧ"',
    "status, is_fiscalized, fiscal (фискальный номер, qr_url, дата, ФИО "
    "курьера, смена).")

# Фискализация
story.append(Paragraph("4.7&nbsp;&nbsp;Фискализация выплат (встроена)", ST["h2"]))
story.append(Paragraph(
    f'Через Webkassa (оператор фискальных данных)&nbsp;&nbsp;&nbsp;{diff("ok")}',
    ST["body"]))
story.append(Paragraph(
    "<b>Что делает.</b> Фискализация уже встроена в /process-payment — "
    "отдельно вызывать ничего не нужно. Поток такой:", ST["body"]))
for p in bullets([
    "вы вызываете /process-payment — мы загружаем заказ в Webkassa;",
    "курьер видит заказ в мобильном приложении Webkassa и пробивает чек;",
    "Webkassa регистрирует чек в КГД и присылает нам уведомление;",
    "мы обновляем статус чека и сохраняем фискальный номер;",
    "вы читаете результат через /receipts/:order_id.",
]):
    story.append(p)
story.append(Paragraph(
    "<b>Для вас это просто.</b> Уведомление от Webkassa приходит на нашу "
    "сторону — вам не нужно интегрироваться ни с Webkassa, ни с КГД. Вы "
    "только читаете /receipts. Договор с оператором фискальных данных — "
    "на нашей стороне.", ST["body"]))

# ─────────────────────────────── 5. Кабинет ────────────────────────────────
story.append(PageBreak())
story.append(Paragraph("5. Кабинет для вашего финотдела", ST["h1"]))
story.append(hr())
story.append(Paragraph(
    "Кроме API есть веб-кабинет — для бухгалтерии и финансового отдела "
    "платформы. Интеграция для него не нужна, просто вход по логину.", ST["body"]))
for p in bullets([
    "статусы всех фискальных чеков с фискальными номерами;",
    "лимит 300 МРП по каждому исполнителю — сколько использовано;",
    "история всех операций и выплат;",
    "экспорт данных для отчётности;",
    "тест каждого сервиса прямо из кабинета — с готовыми примерами.",
]):
    story.append(p)

# ─────────────────────────── 6. Интеграция ─────────────────────────────────
story.append(Paragraph("6. Как интегрироваться", ST["h1"]))
story.append(hr())
story.append(Paragraph(
    "Вся интеграция — это обычные HTTPS-запросы с одним заголовком. "
    "Шаги:", ST["body"]))
steps = [
    ("1", "Получаете API-ключ", "Менеджер Esep выдаёт ключ с нужным вам "
     "набором сервисов."),
    ("2", "Добавляете заголовок", "Ко всем запросам — заголовок "
     "X-Platform-Key с вашим ключом."),
    ("3", "Проверяете ключ", "Первый вызов — GET /api/platform/me. "
     "Убедились, что ключ работает."),
    ("4", "Встраиваете выплату", "В момент выплаты исполнителю ваша система "
     "вызывает /process-payment и действует по полю decision."),
    ("5", "Читаете статусы", "Когда нужно — запрашиваете /receipts/:order_id "
     "для статуса фискального чека."),
]
srows = [[Paragraph(f"<b>{n}</b>", ST["body"]),
          Paragraph(f"<b>{t}</b>", ST["body"]),
          Paragraph(d, ST["body"])] for n, t, d in steps]
t = Table(srows, colWidths=[10*mm, 42*mm, 122*mm])
t.setStyle(TableStyle([
    ('VALIGN', (0,0), (-1,-1), 'TOP'),
    ('LEFTPADDING', (0,0), (-1,-1), 5),
    ('RIGHTPADDING', (0,0), (-1,-1), 5),
    ('TOPPADDING', (0,0), (-1,-1), 5),
    ('BOTTOMPADDING', (0,0), (-1,-1), 5),
    ('BOX', (0,0), (-1,-1), 0.5, BORDER),
    ('LINEBELOW', (0,0), (-1,-1), 0.3, BORDER),
    ('ROWBACKGROUNDS', (0,0), (-1,-1), [colors.white, LIGHT]),
]))
story.append(t)
story.append(Spacer(1, 6))
story.append(Paragraph(
    "<b>Сколько времени.</b> Один разработчик подключает базовый сценарий "
    "(выплата + статус) за <b>1–2 рабочих дня</b>. Не нужно: ставить SDK, "
    "заключать договоры с КГД и операторами фискальных данных, поднимать "
    "свой сервер фискализации.", ST["body"]))

story.append(Paragraph("Сложность по сервисам", ST["h3"]))
diff_rows = [
    [Paragraph("<b>Сервис</b>", ST["small"]),
     Paragraph("<b>Сложность интеграции</b>", ST["small"])],
    [Paragraph("Валидация ИИН", ST["body"]), Paragraph(diff("easy"), ST["body"])],
    [Paragraph("Проверка налогоплательщика", ST["body"]), Paragraph(diff("easy"), ST["body"])],
    [Paragraph("Контроль лимита 300 МРП", ST["body"]), Paragraph(diff("easy"), ST["body"])],
    [Paragraph("Аннулирование заказа", ST["body"]), Paragraph(diff("easy"), ST["body"])],
    [Paragraph("Статус фискального чека", ST["body"]), Paragraph(diff("easy"), ST["body"])],
    [Paragraph("Выплата курьеру (process-payment)", ST["body"]), Paragraph(diff("ok"), ST["body"])],
    [Paragraph("Фискализация (встроена)", ST["body"]), Paragraph(diff("ok"), ST["body"])],
]
t = Table(diff_rows, colWidths=[95*mm, 79*mm])
t.setStyle(TableStyle([
    ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
    ('BACKGROUND', (0,0), (-1,0), NAVY),
    ('TEXTCOLOR', (0,0), (-1,0), colors.white),
    ('LEFTPADDING', (0,0), (-1,-1), 6),
    ('RIGHTPADDING', (0,0), (-1,-1), 6),
    ('TOPPADDING', (0,0), (-1,-1), 5),
    ('BOTTOMPADDING', (0,0), (-1,-1), 5),
    ('BOX', (0,0), (-1,-1), 0.5, BORDER),
    ('LINEBELOW', (0,1), (-1,-1), 0.3, BORDER),
    ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, LIGHT]),
]))
story.append(t)
story.append(Spacer(1, 4))
story.append(Paragraph(
    "Большинство сервисов — один HTTP-запрос, ответ за миллисекунды. "
    "process-payment чуть сложнее только тем, что в вашей системе нужно "
    "обработать три варианта решения (PROCEED / WARNING / BLOCK).", ST["small"]))

# ─────────────────────────── 7. Безопасность ───────────────────────────────
story.append(PageBreak())
story.append(Paragraph("7. Безопасность и доступ", ST["h1"]))
story.append(hr())
for p in bullets([
    "<b>Авторизация</b> — заголовок X-Platform-Key, индивидуальный ключ.",
    "<b>Набор сервисов на ключ</b> — клиент получает только те функции, "
    "что входят в его тариф.",
    "<b>Коды ответов:</b> 401 — нет ключа; 403 — ключ неверный или сервис "
    "не в тарифе; 429 — превышен месячный лимит запросов.",
    "<b>Аудит-журнал</b> — каждый вызов API записывается: для биллинга и "
    "как доказательная база при проверках КГД.",
    "<b>Договоры с КГД и операторами фискальных данных</b> — на стороне "
    "Esep. Вы интегрируетесь только с нашим API.",
    "<b>Тестовая среда</b> — перед боевым подключением выдаётся sandbox "
    "с тестовыми ИИН.",
]):
    story.append(p)

# ─────────────────────────── 8. В разработке ───────────────────────────────
story.append(Paragraph("8. Что в разработке", ST["h1"]))
story.append(hr())
story.append(Paragraph(
    "Честно отделяем рабочее от планируемого. Ещё два сервиса сейчас "
    "в demo-режиме (возвращают тестовые данные с явной пометкой):", ST["body"]))
for p in bullets([
    "<b>Реестр самозанятых</b> — список самозанятых, зарегистрированных в "
    "РК. Требует договора с КГД на API ИСНА.",
    "<b>Льготы самозанятых</b> — категории льгот исполнителя (молодёжь, "
    "многодетные, инвалиды). Также через API ИСНА.",
]):
    story.append(p)
story.append(Paragraph(
    "Договор с КГД на доступ к ИСНА оформляется. Как только доступ получен, "
    "demo-заглушка заменяется на реальные данные без изменения формата "
    "ответа — менять что-либо в вашей интеграции не потребуется.", ST["body"]))

# ─────────────────────────────── Контакты ──────────────────────────────────
story.append(Spacer(1, 16))
story.append(hr())
story.append(Paragraph("Связаться с нами", ST["h2"]))
story.append(Paragraph(
    "Сайт: business.esepkz.com<br/>"
    "WhatsApp / телефон: +7 705 991 47 89<br/>"
    "Документация API: https://api.esepkz.com/api/platform", ST["body"]))
story.append(Spacer(1, 8))
story.append(Paragraph(
    "<i>В документе описаны только реально работающие сервисы. Тарифы для "
    "среднего и крупного бизнеса — индивидуальные, под объём операций.</i>",
    ST["small"]))

doc.build(story)
size_kb = os.path.getsize(OUT) / 1024
print(f"OK: {OUT} ({size_kb:.1f} KB)")
