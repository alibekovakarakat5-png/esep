# -*- coding: utf-8 -*-
"""PDF-приглашение «Esep · Программа экспертов» (1 страница A4) для практикующих бухгалтеров.

Это ВНЕШНИЙ документ для эксперта — только оффер. Внутренняя кухня (модель
мотивации, «честно про деньги», как заходить) остаётся в docs/sales/expert-program.md.

Запуск: py -3.14 docs/_build_expert_pdf.py → Esep-Programma-Ekspertov.pdf в корне."""
import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..'))
OUT = os.path.join(ROOT, 'Esep-Programma-Ekspertov.pdf')
F = r"C:\Windows\Fonts"
pdfmetrics.registerFont(TTFont("DOC", os.path.join(F, "arial.ttf")))
pdfmetrics.registerFont(TTFont("DOC-B", os.path.join(F, "arialbd.ttf")))
pdfmetrics.registerFontFamily("DOC", normal="DOC", bold="DOC-B")
NAVY=colors.HexColor("#0F2B46"); TEAL=colors.HexColor("#0EA5E9"); GREEN=colors.HexColor("#16A34A")
GREY=colors.HexColor("#475569"); WHITE=colors.white
b=getSampleStyleSheet()["Normal"]
def S(n,**k): k.setdefault("fontName","DOC"); return ParagraphStyle(n,parent=b,**k)
title=S("t",fontName="DOC-B",fontSize=24,leading=27,textColor=WHITE)
subt=S("s",fontSize=12,leading=16,textColor=colors.HexColor("#BFE3F7"))
intro=S("i",fontSize=10.5,leading=15,textColor=GREY,spaceAfter=4)
h=S("h",fontName="DOC-B",fontSize=12.5,leading=16,textColor=NAVY,spaceBefore=10,spaceAfter=4)
li=S("li",fontSize=10.5,leading=15,textColor=colors.black,leftIndent=4,spaceAfter=3)
ctaT=S("ct",fontName="DOC-B",fontSize=12,leading=15,textColor=WHITE,alignment=TA_CENTER)
ctaS=S("cs",fontSize=9.5,leading=13,textColor=colors.HexColor("#D1FADF"),alignment=TA_CENTER)

def esc(s): return str(s).replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
story=[]

hdr=Table([[Paragraph("Esep · Программа экспертов",title)],
           [Paragraph("Для практикующих бухгалтеров Казахстана",subt)]],
          colWidths=[170*mm])
hdr.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,-1),NAVY),("LEFTPADDING",(0,0),(-1,-1),16),
    ("RIGHTPADDING",(0,0),(-1,-1),16),("TOPPADDING",(0,0),(0,0),14),("BOTTOMPADDING",(0,0),(0,0),2),
    ("TOPPADDING",(0,1),(0,1),0),("BOTTOMPADDING",(0,1),(0,1),14)]))
story.append(hdr); story.append(Spacer(1,12))

story.append(Paragraph(esc("Esep — казахстанский сервис учёта и налогов под Налоговый кодекс 2026 (формы 910/200/300, ЭСФ, счета и акты, мультиклиент-кабинет для бухгалтерских фирм). В налогах цена ошибки высока, поэтому мы не выпускаем ни одного расчёта и ни одного ответа без проверки практикующим бухгалтером. Ищем экспертов, чьи разборы станут проверенной базой сервиса — под их именем."),intro))

story.append(Paragraph("Что получает эксперт",h))
for t in ["<b>Клиенты в вашу практику</b> — пользователей, которым нужен живой бухгалтер, направляем к вам",
          "<b>Имя и профиль</b> на esepkz.com: бейдж «Проверено экспертом» на выверенных материалах",
          "<b>Статус founding-эксперта</b> — лицо продукта, участие в продуктовых решениях",
          "<b>Полный доступ к Esep бесплатно</b> — весь функционал без ограничений: все ваши клиенты в одном кабинете, формы 910/200/300, счета, акты, ЭСФ, дебиторка, дедлайны",
          "<b>Ваша аудитория растёт</b>: разборы живут в сервисе, а не прокручиваются в чате"]:
    story.append(Paragraph("<font color='#16A34A'><b>✓</b></font>  "+t,li))

story.append(Paragraph("Что делает эксперт",h))
for t in ["Проверяет наши материалы по налогам: нормы, ставки, формы, сроки",
          "По желанию — отвечает на вопросы пользователей (публикуем с вашим именем)",
          "Подсказывает, что на практике устроено иначе, чем в теории"]:
    story.append(Paragraph("<font color='#0EA5E9'><b>•</b></font>  "+esc(t),li))
story.append(Paragraph(esc("Объём — по договорённости, без обязательств «сидеть на потоке». За отдельные крупные блоки работы предусмотрено вознаграждение — обсуждается индивидуально."),intro))

story.append(Paragraph("Почему это важно именно сейчас",h))
story.append(Paragraph(esc("НК-2026 переписал правила: СОНО отключён и всё уходит в ИСНА, НДС 16%, изменились режимы, часть видов деятельности выпала из упрощёнки. Предприниматели теряются, а в чатах расходятся противоречивые ответы. Выигрывает тот источник, за которым стоит имя практика."),intro))

story.append(Paragraph("Как начать",h))
for i,t in enumerate(["15 минут созвона — рассказываем детали, отвечаем на вопросы",
                      "Открываем кабинет и выбираем темы, которые вам близки",
                      "Ваше имя появляется на проверенных материалах, к вам идут клиенты"],1):
    story.append(Paragraph(f"<font color='#0EA5E9'><b>{i}.</b></font>  "+esc(t),li))

story.append(Spacer(1,12))
cta=Table([[Paragraph("Станьте экспертом Esep",ctaT)],
           [Paragraph("WhatsApp +7 705 991 47 89  ·  esepkz.com",ctaS)]],
          colWidths=[170*mm])
cta.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,-1),GREEN),("TOPPADDING",(0,0),(0,0),12),
    ("BOTTOMPADDING",(0,0),(0,0),2),("TOPPADDING",(0,1),(0,1),0),("BOTTOMPADDING",(0,1),(0,1),12)]))
story.append(cta)

SimpleDocTemplate(OUT,pagesize=A4,leftMargin=20*mm,rightMargin=20*mm,topMargin=16*mm,bottomMargin=14*mm,
    title="Esep — Программа экспертов").build(story)
print("OK",os.path.basename(OUT),os.path.getsize(OUT)//1024,"KB")
