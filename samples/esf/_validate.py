"""Validate sample ЭСФ XML files for well-formedness and key structure.
Run: python samples/esf/_validate.py
"""
import os
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))

REQUIRED_PATHS_NOVAT = [
    "HEADER/INVOICE_NUM",
    "HEADER/INVOICE_DATE",
    "HEADER/TYPE",
    "SELLER/IIN",
    "SELLER/NAME",
    "SELLER/IS_VAT_PAYER",
    "BUYER/NAME",
    "TURNOVER/PRODUCT/NUM",
    "TURNOVER/PRODUCT/DESCRIPTION",
    "TURNOVER/PRODUCT/UNIT_CODE",
    "TURNOVER/PRODUCT/UNIT_NAME",
    "TURNOVER/PRODUCT/NET_TURNOVER",
    "TURNOVER/PRODUCT/NDS_RATE",
    "TURNOVER/PRODUCT/NDS_SUM",
    "TURNOVER/PRODUCT/TURNOVER_WITH_NDS",
    "TOTAL/TOTAL_NET_TURNOVER",
    "TOTAL/TOTAL_NDS",
    "TOTAL/TOTAL_TURNOVER_WITH_NDS",
]

CASES = [
    ("esf-novat.xml",       True,  "WITHOUT_NDS", "false"),
    ("esf-vat.xml",         True,  "NDS_16",      "true"),
    ("esf-missing-iin.xml", True,  "WITHOUT_NDS", "false"),
    ("esf-incomplete.xml",  True,  "WITHOUT_NDS", "false"),
]

def validate(filename, must_parse, expected_nds_rate, expected_is_vat):
    path = os.path.join(HERE, filename)
    issues = []

    # 1. Parse
    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        return [f"❌ XML PARSE ERROR: {e}"], None

    root = tree.getroot()
    if root.tag != "ESF":
        issues.append(f"⚠ root tag = {root.tag}, ожидалось ESF")

    # 2. Required paths
    for p in REQUIRED_PATHS_NOVAT:
        if root.find(p) is None:
            issues.append(f"❌ missing required path: {p}")

    # 3. NDS_RATE consistency
    rate = root.find("TURNOVER/PRODUCT/NDS_RATE")
    if rate is not None and rate.text != expected_nds_rate:
        issues.append(f"❌ NDS_RATE = {rate.text}, ожидалось {expected_nds_rate}")

    # 4. IS_VAT_PAYER
    isvat = root.find("SELLER/IS_VAT_PAYER")
    if isvat is not None and isvat.text != expected_is_vat:
        issues.append(f"❌ IS_VAT_PAYER = {isvat.text}, ожидалось {expected_is_vat}")

    # 5. Math consistency: TOTAL_NDS = sum of product NDS_SUM; TOTAL_NET = sum of NET_TURNOVER
    def fnum(el):
        return float(el.text) if el is not None and el.text else 0.0
    sum_net = sum(fnum(p.find("NET_TURNOVER")) for p in root.findall("TURNOVER/PRODUCT"))
    sum_nds = sum(fnum(p.find("NDS_SUM")) for p in root.findall("TURNOVER/PRODUCT"))
    sum_gross = sum(fnum(p.find("TURNOVER_WITH_NDS")) for p in root.findall("TURNOVER/PRODUCT"))

    total_net = fnum(root.find("TOTAL/TOTAL_NET_TURNOVER"))
    total_nds = fnum(root.find("TOTAL/TOTAL_NDS"))
    total_gross = fnum(root.find("TOTAL/TOTAL_TURNOVER_WITH_NDS"))

    if abs(total_net - sum_net) > 0.01:
        issues.append(f"❌ TOTAL_NET_TURNOVER ({total_net}) != сумма NET по позициям ({sum_net})")
    if abs(total_nds - sum_nds) > 0.01:
        issues.append(f"❌ TOTAL_NDS ({total_nds}) != сумма NDS_SUM ({sum_nds})")
    if abs(total_gross - sum_gross) > 0.01:
        issues.append(f"❌ TOTAL_TURNOVER_WITH_NDS ({total_gross}) != сумма TURNOVER_WITH_NDS ({sum_gross})")

    # 6. VAT math when IS_VAT_PAYER = true
    if expected_is_vat == "true":
        for p in root.findall("TURNOVER/PRODUCT"):
            net = fnum(p.find("NET_TURNOVER"))
            nds = fnum(p.find("NDS_SUM"))
            expected_nds = round(net * 0.16, 2)
            if abs(nds - expected_nds) > 0.01:
                issues.append(f"❌ В строке: NDS_SUM={nds}, ожидалось {expected_nds} (16% от NET {net})")

    # 7. VAT math when not payer = NDS_SUM should be 0
    if expected_is_vat == "false":
        for p in root.findall("TURNOVER/PRODUCT"):
            nds = fnum(p.find("NDS_SUM"))
            if nds != 0:
                issues.append(f"❌ NDS_SUM = {nds} при IS_VAT_PAYER=false, должно быть 0.00")

    return issues, {
        "total_net": total_net,
        "total_nds": total_nds,
        "total_gross": total_gross,
    }


def main():
    print(f"{'File':32s} {'Status':10s} {'Net':>12s} {'НДС':>10s} {'Brutto':>12s}")
    print("-" * 80)
    any_fail = False
    for filename, must_parse, expected_rate, expected_isvat in CASES:
        issues, totals = validate(filename, must_parse, expected_rate, expected_isvat)
        status = "OK" if not issues else "FAIL"
        if issues:
            any_fail = True
        net = f"{totals['total_net']:>12,.2f}" if totals else "      —"
        nds = f"{totals['total_nds']:>10,.2f}" if totals else "      —"
        gr  = f"{totals['total_gross']:>12,.2f}" if totals else "      —"
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
