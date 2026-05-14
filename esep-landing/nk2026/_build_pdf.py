# -*- coding: utf-8 -*-
"""Сборка PDF-курса «НК РК 2026 за полчаса» из 10 базовых HTML-уроков.

Контент берётся КАК ЕСТЬ из статей esep-landing/nk2026/*.html — факты не
переписываются (ждут проверки бухгалтера). Запуск:

    python esep-landing/nk2026/_build_pdf.py

Результат: esep-landing/nk2026/kurs-nk-2026-chernovik.pdf
"""
import os
import sys

from bs4 import BeautifulSoup, NavigableString, Tag
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle,
    ListFlowable, ListItem, HRFlowable,
)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "kurs-nk-2026-chernovik.pdf")

# Порядок 10 базовых уроков (slug, как в admin.js)
LESSONS = [
    "mrp-mzp",
    "uproshenka-910",
    "nds-16",
    "nds-osvobozhdenie",
    "opvr-3-5",
    "so-5",
    "ipn-progressivnyy",
    "sn-too",
    "samozanyatye",
    "dedlayny-2026",
]

# ── Шрифты с кириллицей (Windows Arial) ──────────────────────────────────────
FONT_DIR = r"C:\Windows\Fonts"
pdfmetrics.registerFont(TTFont("NK", os.path.join(FONT_DIR, "arial.ttf")))
pdfmetrics.registerFont(TTFont("NK-B", os.path.join(FONT_DIR, "arialbd.ttf")))
pdfmetrics.registerFont(TTFont("NK-I", os.path.join(FONT_DIR, "ariali.ttf")))
pdfmetrics.registerFontFamily("NK", normal="NK", bold="NK-B", italic="NK-I")

NAVY = colors.HexColor("#0F2B46")
GREY = colors.HexColor("#6b7280")
RED = colors.HexColor("#dc2626")
GREEN = colors.HexColor("#16a34a")
LIGHT = colors.HexColor("#f1f5f9")
BORDER = colors.HexColor("#cbd5e1")

styles = getSampleStyleSheet()


def S(name, **kw):
    base = kw.pop("parent", styles["Normal"])
    kw.setdefault("fontName", "NK")
    return ParagraphStyle(name, parent=base, **kw)


ST = {
    "cover_title": S("cover_title", fontName="NK-B", fontSize=30, leading=36,
                     textColor=NAVY, alignment=TA_CENTER, spaceAfter=10),
    "cover_sub": S("cover_sub", fontSize=14, leading=20, textColor=GREY,
                   alignment=TA_CENTER, spaceAfter=6),
    "h1": S("h1", fontName="NK-B", fontSize=20, leading=25, textColor=NAVY,
            spaceBefore=4, spaceAfter=4),
    "badge": S("badge", fontName="NK-B", fontSize=10, leading=12,
               textColor=colors.white, backColor=NAVY),
    "meta": S("meta", fontSize=9, leading=12, textColor=GREY, spaceAfter=8),
    "h2": S("h2", fontName="NK-B", fontSize=14, leading=18, textColor=NAVY,
            spaceBefore=12, spaceAfter=5),
    "h3": S("h3", fontName="NK-B", fontSize=11.5, leading=15, textColor=NAVY,
            spaceBefore=8, spaceAfter=3),
    "body": S("body", fontSize=10.5, leading=15, spaceAfter=5),
    "tldr": S("tldr", fontSize=10.5, leading=15, spaceAfter=4,
              backColor=LIGHT, borderColor=NAVY, borderWidth=0,
              leftIndent=8, rightIndent=8, spaceBefore=4),
    "li": S("li", fontSize=10.5, leading=15),
    "faq_q": S("faq_q", fontName="NK-B", fontSize=10.5, leading=14,
               textColor=NAVY, spaceBefore=6, spaceAfter=2),
    "src": S("src", fontSize=9, leading=13, textColor=GREY, spaceAfter=3),
    "toc": S("toc", fontSize=11.5, leading=20),
    "cell": S("cell", fontSize=9, leading=12),
    "cell_b": S("cell_b", fontName="NK-B", fontSize=9, leading=12),
    "disc": S("disc", fontSize=10, leading=14, textColor=colors.HexColor("#92400e")),
}


def inline(node):
    """HTML-узел → строка с разметкой reportlab (<b>, <i>, <font color>)."""
    out = []
    for child in node.children:
        if isinstance(child, NavigableString):
            out.append(str(child).replace("&", "&amp;").replace("<", "&lt;")
                       .replace(">", "&gt;"))
        elif isinstance(child, Tag):
            inner = inline(child)
            cls = " ".join(child.get("class", []))
            if child.name in ("strong", "b"):
                out.append("<b>%s</b>" % inner)
            elif child.name in ("em", "i"):
                out.append("<i>%s</i>" % inner)
            elif child.name == "a":
                out.append(inner)  # ссылки в PDF разворачиваем в текст
            elif child.name == "br":
                out.append("<br/>")
            elif "delta-neg" in cls:
                out.append('<font color="#dc2626">%s</font>' % inner)
            elif "delta-pos" in cls:
                out.append('<font color="#16a34a">%s</font>' % inner)
            else:
                out.append(inner)
    return "".join(out).strip()


def build_table(tag):
    """HTML <table> → reportlab Table с поддержкой colspan."""
    rows, spans, styles_cmd = [], [], []
    r = 0
    for tr in tag.find_all("tr"):
        cells, c = [], 0
        is_head = tr.find_parent("thead") is not None
        for td in tr.find_all(["td", "th"]):
            txt = inline(td)
            st = ST["cell_b"] if (is_head or td.name == "th") else ST["cell"]
            cells.append(Paragraph(txt, st))
            cspan = int(td.get("colspan", 1))
            if cspan > 1:
                styles_cmd.append(("SPAN", (c, r), (c + cspan - 1, r)))
                cells.extend([""] * (cspan - 1))
                c += cspan
            else:
                c += 1
        rows.append(cells)
        if is_head:
            styles_cmd.append(("BACKGROUND", (0, r), (-1, r), NAVY))
            styles_cmd.append(("TEXTCOLOR", (0, r), (-1, r), colors.white))
        r += 1
    # выровнять длину строк
    width = max(len(x) for x in rows)
    for x in rows:
        x.extend([""] * (width - len(x)))
    t = Table(rows, repeatRows=1, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, LIGHT]),
    ] + styles_cmd))
    return t


def build_list(tag):
    items = []
    for li in tag.find_all("li", recursive=False):
        items.append(ListItem(Paragraph(inline(li), ST["li"]), leftIndent=14))
    bullet = "1" if tag.name == "ol" else "bullet"
    return ListFlowable(items, bulletType=bullet, start="1",
                        bulletColor=NAVY, leftIndent=10, spaceBefore=2,
                        spaceAfter=6)


def parse_lesson(slug):
    """HTML-урок → список flowables reportlab."""
    with open(os.path.join(HERE, slug + ".html"), encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), "html.parser")
    container = soup.find("div", class_="container")
    flow = []
    badge_num = ""

    for el in container.children:
        if not isinstance(el, Tag):
            continue
        cls = " ".join(el.get("class", []))

        if el.name == "span" and "badge" == cls:
            badge_num = el.get_text(strip=True)
        elif el.name == "h1":
            if badge_num:
                flow.append(Paragraph(badge_num, ST["badge"]))
                flow.append(Spacer(1, 3))
            flow.append(Paragraph(inline(el), ST["h1"]))
        elif el.name == "div" and "meta" in cls:
            flow.append(Paragraph(inline(el), ST["meta"]))
            flow.append(HRFlowable(width="100%", thickness=0.6, color=BORDER,
                                   spaceBefore=2, spaceAfter=8))
        elif el.name == "div" and "tldr" in cls:
            for sub in el.children:
                if isinstance(sub, Tag):
                    if sub.name == "h2":
                        flow.append(Paragraph("⚡ " + inline(sub), ST["h3"]))
                    elif sub.name == "p":
                        flow.append(Paragraph(inline(sub), ST["tldr"]))
            flow.append(Spacer(1, 6))
        elif el.name == "h2":
            flow.append(Paragraph(inline(el), ST["h2"]))
        elif el.name == "h3":
            flow.append(Paragraph(inline(el), ST["h3"]))
        elif el.name == "p":
            flow.append(Paragraph(inline(el), ST["body"]))
        elif el.name in ("ul", "ol"):
            flow.append(build_list(el))
        elif el.name == "table":
            flow.append(Spacer(1, 2))
            flow.append(build_table(el))
            flow.append(Spacer(1, 8))
        elif el.name == "div" and "example" in cls:
            for sub in el.children:
                if not isinstance(sub, Tag):
                    continue
                scls = " ".join(sub.get("class", []))
                if "label" in scls:
                    flow.append(Paragraph(inline(sub).upper(), ST["h3"]))
                elif sub.name in ("h4", "h3"):
                    flow.append(Paragraph(inline(sub), ST["faq_q"]))
                elif sub.name == "p":
                    flow.append(Paragraph(inline(sub), ST["body"]))
                elif sub.name in ("ul", "ol"):
                    flow.append(build_list(sub))
        elif el.name == "details":
            summary = el.find("summary")
            if summary:
                flow.append(Paragraph("❓ " + inline(summary), ST["faq_q"]))
            for sub in el.children:
                if isinstance(sub, Tag) and sub.name == "p":
                    flow.append(Paragraph(inline(sub), ST["body"]))
                elif isinstance(sub, Tag) and sub.name in ("ul", "ol"):
                    flow.append(build_list(sub))
        elif el.name == "div" and "sources" in cls:
            flow.append(Paragraph("Источники", ST["h3"]))
            for li in el.find_all("li"):
                flow.append(Paragraph("• " + inline(li), ST["src"]))
        # crumbs, badge-tag, calc-cta, read-also — пропускаем

    return flow


def cover_and_toc():
    flow = [Spacer(1, 60 * mm)]
    flow.append(Paragraph("НК РК 2026<br/>за полчаса", ST["cover_title"]))
    flow.append(Spacer(1, 6))
    flow.append(Paragraph("Мини-курс по налоговым изменениям для ИП и бухгалтеров",
                          ST["cover_sub"]))
    flow.append(Paragraph("10 базовых уроков · расчёты · примеры", ST["cover_sub"]))
    flow.append(Spacer(1, 20 * mm))
    disc = ("<b>ЧЕРНОВИК.</b> Материал на проверке у бухгалтера. Не является "
            "официальной налоговой консультацией. Перед применением сверяйтесь "
            "с действующей редакцией НК РК (Закон № 214-VIII) на adilet.zan.kz.")
    disc_t = Table([[Paragraph(disc, ST["disc"])]], colWidths=[150 * mm])
    disc_t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#fef3c7")),
        ("BOX", (0, 0), (-1, -1), 0.8, colors.HexColor("#f59e0b")),
        ("TOPPADDING", (0, 0), (-1, -1), 10),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
        ("LEFTPADDING", (0, 0), (-1, -1), 12),
        ("RIGHTPADDING", (0, 0), (-1, -1), 12),
    ]))
    flow.append(disc_t)
    flow.append(Spacer(1, 14 * mm))
    flow.append(Paragraph("Esep · esepkz.com · май 2026", ST["cover_sub"]))
    flow.append(PageBreak())

    # Оглавление
    flow.append(Paragraph("Содержание", ST["h1"]))
    flow.append(HRFlowable(width="100%", thickness=0.6, color=BORDER,
                           spaceBefore=4, spaceAfter=10))
    titles = []
    for slug in LESSONS:
        with open(os.path.join(HERE, slug + ".html"), encoding="utf-8") as f:
            s = BeautifulSoup(f.read(), "html.parser")
        h1 = s.find("h1").get_text(strip=True)
        badge = s.find("span", class_="badge").get_text(strip=True)
        titles.append((badge, h1))
    for badge, title in titles:
        flow.append(Paragraph("<b>%s.</b>&nbsp;&nbsp;%s" % (badge, title),
                              ST["toc"]))
    flow.append(PageBreak())
    return flow


def main():
    doc = SimpleDocTemplate(
        OUT, pagesize=A4,
        leftMargin=22 * mm, rightMargin=22 * mm,
        topMargin=20 * mm, bottomMargin=18 * mm,
        title="НК РК 2026 за полчаса — мини-курс (черновик)",
        author="Esep",
    )
    story = cover_and_toc()
    for i, slug in enumerate(LESSONS):
        story.extend(parse_lesson(slug))
        if i != len(LESSONS) - 1:
            story.append(PageBreak())

    def footer(canvas, d):
        canvas.saveState()
        canvas.setFont("NK", 8)
        canvas.setFillColor(GREY)
        canvas.drawCentredString(A4[0] / 2, 10 * mm,
                                 "НК РК 2026 за полчаса · черновик · esepkz.com")
        if d.page > 1:
            canvas.drawRightString(A4[0] - 22 * mm, 10 * mm, str(d.page))
        canvas.restoreState()

    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    size = os.path.getsize(OUT)
    print("OK: %s (%.1f KB, %d уроков)" % (OUT, size / 1024, len(LESSONS)))


if __name__ == "__main__":
    main()
