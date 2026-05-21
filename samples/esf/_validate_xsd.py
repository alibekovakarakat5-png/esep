# -*- coding: utf-8 -*-
"""Валидация сгенерированных ЭСФ XML против официальных XSD-схем КГД.

XSD взяты из ESF SDK 28.08.2024 (api-wsdl/xsd/Invoice/):
  - InvoiceContainer.xsd  (namespace "esf")
  - InvoiceV2.xsd         (namespace "v2.esf")
  - InvoiceV1.xsd         (namespace "abstractInvoice.esf")

Импорты в схемах без schemaLocation — добавляем их в памяти, чтобы
lxml корректно собрал составную схему.

Запуск: python samples/esf/_validate_xsd.py
"""
import io
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass

try:
    from lxml import etree
except ImportError:
    print("ERROR: нужен lxml — pip install --user lxml")
    sys.exit(1)

HERE = os.path.dirname(os.path.abspath(__file__))
XSD_DIR = os.path.join(HERE, "xsd")

# ── Патчим импорты XSD: добавляем schemaLocation ────────────────────────────
# InvoiceContainer импортирует v1.esf и v2.esf без schemaLocation.
# InvoiceV2 импортирует abstractInvoice.esf без schemaLocation.

def read(name):
    with open(os.path.join(XSD_DIR, name), "r", encoding="utf-8") as f:
        return f.read()

# v1.esf stub — мы валидируем только v2:invoice, реального v1.esf нет.
V1_STUB = '''<?xml version="1.0" encoding="UTF-8"?>
<xs:schema targetNamespace="v1.esf" xmlns:tns="v1.esf"
           xmlns:xs="http://www.w3.org/2001/XMLSchema">
  <xs:element name="invoice" type="xs:anyType"/>
</xs:schema>'''

with open(os.path.join(XSD_DIR, "_v1stub.xsd"), "w", encoding="utf-8") as f:
    f.write(V1_STUB)

# Патчим InvoiceV2.xsd — импорт abstractInvoice.esf → InvoiceV1.xsd
v2 = read("InvoiceV2.xsd")
v2 = v2.replace(
    '<xs:import namespace="abstractInvoice.esf"/>',
    '<xs:import namespace="abstractInvoice.esf" schemaLocation="InvoiceV1.xsd"/>')
with open(os.path.join(XSD_DIR, "_v2_patched.xsd"), "w", encoding="utf-8") as f:
    f.write(v2)

# Патчим InvoiceContainer.xsd — ссылка на ПРОПАТЧЕННЫЙ v2
container = read("InvoiceContainer.xsd")
container = container.replace(
    '<xs:import namespace="v1.esf"/>',
    '<xs:import namespace="v1.esf" schemaLocation="_v1stub.xsd"/>')
container = container.replace(
    '<xs:import namespace="v2.esf"/>',
    '<xs:import namespace="v2.esf" schemaLocation="_v2_patched.xsd"/>')
with open(os.path.join(XSD_DIR, "_container_patched.xsd"), "w", encoding="utf-8") as f:
    f.write(container)

# ── Загружаем составную схему ────────────────────────────────────────────────
try:
    schema_doc = etree.parse(os.path.join(XSD_DIR, "_container_patched.xsd"))
    schema = etree.XMLSchema(schema_doc)
    print("✅  XSD-схема загружена (InvoiceContainer + InvoiceV2 + InvoiceV1)")
except Exception as e:
    print(f"❌  Не удалось загрузить XSD: {e}")
    sys.exit(1)

# ── Валидируем образцы ──────────────────────────────────────────────────────
SAMPLES = ["esf-vat.xml", "esf-novat.xml"]

print()
all_ok = True
for name in SAMPLES:
    path = os.path.join(HERE, name)
    if not os.path.exists(path):
        print(f"⚠  {name} — файл не найден, пропуск")
        continue
    try:
        doc = etree.parse(path)
    except Exception as e:
        print(f"❌  {name} — XML не парсится: {e}")
        all_ok = False
        continue

    if schema.validate(doc):
        print(f"✅  {name} — ВАЛИДЕН по официальной XSD КГД")
    else:
        all_ok = False
        print(f"❌  {name} — НЕ прошёл валидацию:")
        for err in schema.error_log:
            print(f"     строка {err.line}: {err.message}")

print()
print("━" * 60)
if all_ok:
    print("  ИТОГ: все образцы валидны по XSD ✅")
else:
    print("  ИТОГ: есть ошибки — см. выше ❌")
print("━" * 60)
sys.exit(0 if all_ok else 1)
