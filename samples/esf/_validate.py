"""Validate sample ЭСФ XML files (формат контейнера импорта ИС ЭСФ).

Структура: esf:invoiceInfoContainer → invoiceBody (CDATA) → v2:invoice.
Скрипт парсит контейнер, извлекает CDATA-тело и проверяет v2:invoice.

Run: python samples/esf/_validate.py
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

# Консоль Windows по умолчанию cp1251 — переключаем на utf-8 для emoji/кириллицы.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass

HERE = os.path.dirname(os.path.abspath(__file__))

# Внутри v2:invoice в namespace только корень; дочерние теги без префикса.
V2_ROOT = "{v2.esf}invoice"

# Обязательные пути внутри v2:invoice
REQUIRED_PATHS = [
    "date",
    "invoiceType",
    "num",
    "operatorFullname",
    "turnoverDate",
    "consignee/name",
    "consignor/name",
    "customers/customer/name",
    "deliveryTerm/hasContract",
    "productSet/currencyCode",
    "productSet/products/product/description",
    "productSet/products/product/priceWithoutTax",
    "productSet/products/product/ndsAmount",
    "productSet/products/product/priceWithTax",
    "productSet/products/product/quantity",
    "productSet/products/product/unitPrice",
    "productSet/totalNdsAmount",
    "productSet/totalPriceWithoutTax",
    "productSet/totalPriceWithTax",
    "sellers/seller/tin",
    "sellers/seller/name",
]

CASES = [
    ("esf-novat.xml",       False),  # (файл, плательщик НДС)
    ("esf-vat.xml",         True),
    ("esf-missing-iin.xml", False),
    ("esf-incomplete.xml",  False),
]


def extract_invoice(path):
    """Парсит контейнер, достаёт CDATA-тело, возвращает корень v2:invoice."""
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()

    # 1. Контейнер должен быть well-formed
    ET.fromstring(raw)

    # 2. Извлекаем CDATA из invoiceBody
    m = re.search(r"<invoiceBody><!\[CDATA\[(.*?)\]\]></invoiceBody>", raw, re.S)
    if not m:
        raise ValueError("invoiceBody CDATA не найден")
    body = m.group(1)

    # 3. Парсим внутренний v2:invoice
    return ET.fromstring(body)


def validate(filename, is_vat):
    path = os.path.join(HERE, filename)
    issues = []

    try:
        inv = extract_invoice(path)
    except (ET.ParseError, ValueError) as e:
        return [f"❌ XML PARSE ERROR: {e}"], None

    if inv.tag != V2_ROOT:
        issues.append(f"⚠ root tag = {inv.tag}, ожидалось {V2_ROOT}")

    for p in REQUIRED_PATHS:
        if inv.find(p) is None:
            issues.append(f"❌ missing required path: {p}")

    def fnum(el):
        return float(el.text) if el is not None and el.text else 0.0

    products = inv.findall("productSet/products/product")
    sum_net = sum(fnum(p.find("priceWithoutTax")) for p in products)
    sum_nds = sum(fnum(p.find("ndsAmount")) for p in products)
    sum_gross = sum(fnum(p.find("priceWithTax")) for p in products)

    total_net = fnum(inv.find("productSet/totalPriceWithoutTax"))
    total_nds = fnum(inv.find("productSet/totalNdsAmount"))
    total_gross = fnum(inv.find("productSet/totalPriceWithTax"))

    if abs(total_net - sum_net) > 0.01:
        issues.append(f"❌ totalPriceWithoutTax ({total_net}) != сумма по позициям ({sum_net})")
    if abs(total_nds - sum_nds) > 0.01:
        issues.append(f"❌ totalNdsAmount ({total_nds}) != сумма ndsAmount ({sum_nds})")
    if abs(total_gross - sum_gross) > 0.01:
        issues.append(f"❌ totalPriceWithTax ({total_gross}) != сумма priceWithTax ({sum_gross})")

    # НДС-математика
    for p in products:
        net = fnum(p.find("priceWithoutTax"))
        nds = fnum(p.find("ndsAmount"))
        if is_vat:
            expected = round(net * 0.16, 2)
            if abs(nds - expected) > 0.01:
                issues.append(f"❌ В строке: ndsAmount={nds}, ожидалось {expected} (16% от {net})")
        else:
            if nds != 0:
                issues.append(f"❌ ndsAmount={nds} для не-плательщика НДС, должно быть 0")

    return issues, {
        "total_net": total_net,
        "total_nds": total_nds,
        "total_gross": total_gross,
    }


def main():
    print(f"{'File':32s} {'Status':10s} {'Net':>14s} {'НДС':>12s} {'Brutto':>14s}")
    print("-" * 86)
    any_fail = False
    for filename, is_vat in CASES:
        issues, totals = validate(filename, is_vat)
        status = "OK" if not issues else "FAIL"
        if issues:
            any_fail = True
        net = f"{totals['total_net']:>14,.2f}" if totals else "      —"
        nds = f"{totals['total_nds']:>12,.2f}" if totals else "      —"
        gr = f"{totals['total_gross']:>14,.2f}" if totals else "      —"
        print(f"{filename:32s} {status:10s} {net} {nds} {gr}")
        for it in issues:
            print(f"    {it}")
    print()
    if any_fail:
        print("❌ Есть проблемы — см. выше")
        sys.exit(1)
    else:
        print("✅ Все XML well-formed и проходят структурные проверки")


if __name__ == "__main__":
    main()
