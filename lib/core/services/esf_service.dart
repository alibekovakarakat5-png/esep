import 'package:intl/intl.dart';

import '../models/invoice.dart';
import '../providers/company_provider.dart';
import '../constants/kz_tax_constants.dart';

/// Результат валидации перед генерацией ЭСФ
class EsfValidation {
  /// Блокирующие ошибки — XML не должен генерироваться
  final List<String> errors;
  /// Предупреждения — XML генерируется, но клиента надо предупредить
  final List<String> warnings;

  const EsfValidation({this.errors = const [], this.warnings = const []});

  bool get isValid => errors.isEmpty;
  bool get hasIssues => errors.isNotEmpty || warnings.isNotEmpty;
}

/// Генератор ЭСФ XML для ИС ЭСФ КГД РК.
///
/// Формат — официальный контейнер импорта (сверено с эталоном SDK
/// `One InvoiceV2.xml`, ESF SDK 28.08.2024):
/// `esf:invoiceContainer` → `invoiceSet` → `v2:invoice` (напрямую, без CDATA).
///
/// ⚠ ВАЖНО: используется `invoiceContainer` (для импорта/загрузки),
/// НЕ `invoiceInfoContainer` (тот — для получения данных о чеке).
///
/// Системные поля (invoiceId, registrationNumber, signature, certificate,
/// invoiceStatus и т.д.) не выводятся — их присваивает ИС ЭСФ при
/// регистрации. ЭЦП пользователь ставит на портале при загрузке.
class EsfService {
  EsfService._();

  static final _dateFmt = DateFormat('dd.MM.yyyy');

  /// Проверка готовности данных для генерации ЭСФ.
  /// Используйте перед `generate()`.
  static EsfValidation validate(Invoice invoice, CompanyInfo company) {
    final errors = <String>[];
    final warnings = <String>[];

    // Данные поставщика
    if (company.name.isEmpty) {
      errors.add('Не заполнено название/ФИО поставщика (Настройки → Компания)');
    }
    if (company.iin.isEmpty) {
      errors.add('Не заполнен ИИН/БИН поставщика (Настройки → Компания)');
    } else if (company.iin.length != 12) {
      errors.add('ИИН/БИН поставщика должен содержать 12 цифр');
    }
    if (company.operatorFullname == null ||
        company.operatorFullname!.trim().isEmpty) {
      errors.add(
          'Не заполнено ФИО оператора (Настройки → Компания) — '
          'обязательно для ЭСФ');
    }

    // Данные покупателя
    if (invoice.clientName.isEmpty) {
      errors.add('Не указано имя покупателя');
    }
    if (invoice.buyerIin == null || invoice.buyerIin!.isEmpty) {
      warnings.add(
          'ИИН/БИН покупателя не указан — ЭСФ не примет получатель-юрлицо. '
          'Заполните для отгрузки ИП/ТОО.');
    } else if (invoice.buyerIin!.length != 12) {
      errors.add('ИИН/БИН покупателя должен содержать 12 цифр');
    }

    // Грузоотправитель / грузополучатель
    if (!invoice.consignorSameAsSeller &&
        (invoice.consignorName == null ||
            invoice.consignorName!.trim().isEmpty)) {
      errors.add('Не заполнено название грузоотправителя');
    }
    if (!invoice.consigneeSameAsCustomer &&
        (invoice.consigneeName == null ||
            invoice.consigneeName!.trim().isEmpty)) {
      errors.add('Не заполнено название грузополучателя');
    }

    // Позиции
    if (invoice.items.isEmpty) {
      errors.add('В счёте нет ни одной позиции');
    }
    for (final item in invoice.items) {
      if (item.esfUnitCode == null || item.esfUnitCode!.trim().isEmpty) {
        warnings.add(
            'Позиция «${item.description}»: не заполнен код единицы измерения '
            'ЭСФ — возьмите его из своей учётной системы (1С).');
      }
    }

    // Банковские реквизиты — мягкое предупреждение
    if (company.iik == null || company.iik!.isEmpty) {
      warnings.add(
          'Не заполнен ИИК (IBAN) поставщика — покупатель не увидит реквизиты для оплаты.');
    }

    // Номер ЭСФ по XSD КГД — строго числовой. Если в номере счёта нет цифр,
    // будет подставлен timestamp — он не совпадёт с нумерацией бухгалтерии.
    if (invoice.number.replaceAll(RegExp(r'[^0-9]'), '').isEmpty) {
      warnings.add(
          'Номер счёта не содержит цифр. Номер ЭСФ должен быть числовым — '
          'будет сгенерирован автоматически. Рекомендуем нумеровать счета '
          'с числами (например «2026-001»).');
    }

    return EsfValidation(errors: errors, warnings: warnings);
  }

  /// Генерирует XML строку ЭСФ в формате контейнера импорта ИС ЭСФ.
  /// Если `company.isVatPayer == true` — товары/услуги облагаются НДС 16%.
  /// Сумма строки трактуется как **без НДС** (net), НДС начисляется сверху.
  ///
  /// Формат: `esf:invoiceContainer` → `invoiceSet` → `v2:invoice` напрямую
  /// (сверено с эталоном SDK `One InvoiceV2.xml`).
  static String generate(Invoice invoice, CompanyInfo company) {
    final body = _buildInvoiceBody(invoice, company);
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<esf:invoiceContainer xmlns:esf="esf">\n'
        '    <invoiceSet>\n'
        '$body\n'
        '    </invoiceSet>\n'
        '</esf:invoiceContainer>';
  }

  /// Документ `v2:invoice` — помещается напрямую в `invoiceSet` (без CDATA).
  static String _buildInvoiceBody(Invoice invoice, CompanyInfo company) {
    final isVat = company.isVatPayer;
    final vatRate = KzTax.vatRate; // 0.16
    final invoiceDate = _dateFmt.format(invoice.createdAt);
    final turnoverDate =
        _dateFmt.format(invoice.turnoverDate ?? invoice.createdAt);
    final operator = (company.operatorFullname != null &&
            company.operatorFullname!.trim().isNotEmpty)
        ? company.operatorFullname!.trim()
        : company.name;

    double totalNet = 0;
    double totalVat = 0;
    double totalGross = 0;

    final products = invoice.items.map((item) {
      final net = item.total;
      final vat = isVat ? net * vatRate : 0.0;
      final gross = net + vat;
      totalNet += net;
      totalVat += vat;
      totalGross += gross;

      final unitNomenclature =
          (item.esfUnitCode != null && item.esfUnitCode!.trim().isNotEmpty)
              ? '\n                <unitNomenclature>${_esc(item.esfUnitCode!.trim())}</unitNomenclature>'
              : '';

      // ndsRate выводится только для облагаемых НДС позиций.
      // Порядок тегов алфавитный — ndsRate идёт сразу после ndsAmount.
      final ndsRate = isVat
          ? '\n                <ndsRate>${(vatRate * 100).round()}</ndsRate>'
          : '';

      return '''            <product>
                <catalogTruId>${_esc(item.catalogTruId)}</catalogTruId>
                <description>${_esc(item.description)}</description>
                <ndsAmount>${_num(vat)}</ndsAmount>$ndsRate
                <priceWithTax>${_num(gross)}</priceWithTax>
                <priceWithoutTax>${_num(net)}</priceWithoutTax>
                <quantity>${_num(item.quantity)}</quantity>
                <truOriginCode>${_esc(item.truOriginCode)}</truOriginCode>
                <turnoverSize>${_num(net)}</turnoverSize>$unitNomenclature
                <unitPrice>${_num(item.unitPrice)}</unitPrice>
            </product>''';
    }).join('\n');

    // Грузоотправитель — поставщик или отдельные реквизиты
    final consignorAddress = invoice.consignorSameAsSeller
        ? (company.address ?? '')
        : (invoice.consignorAddress ?? '');
    final consignorName =
        invoice.consignorSameAsSeller ? company.name : (invoice.consignorName ?? '');
    final consignorTin =
        invoice.consignorSameAsSeller ? company.iin : (invoice.consignorTin ?? '');

    // Грузополучатель — покупатель или отдельные реквизиты
    final consigneeAddress = invoice.consigneeSameAsCustomer
        ? ''
        : (invoice.consigneeAddress ?? '');
    final consigneeName = invoice.consigneeSameAsCustomer
        ? invoice.clientName
        : (invoice.consigneeName ?? '');
    final consigneeTin = invoice.consigneeSameAsCustomer
        ? (invoice.buyerIin ?? '')
        : (invoice.consigneeTin ?? '');

    // Договор-основание
    final deliveryTerm = StringBuffer('    <deliveryTerm>\n');
    if (invoice.hasContract) {
      if (invoice.contractDate != null) {
        deliveryTerm.write(
            '        <contractDate>${_dateFmt.format(invoice.contractDate!)}</contractDate>\n');
      }
      deliveryTerm.write(
          '        <contractNum>${_esc(invoice.contractNum!)}</contractNum>\n');
      deliveryTerm.write('        <hasContract>true</hasContract>\n');
    } else {
      deliveryTerm.write('        <hasContract>false</hasContract>\n');
    }
    deliveryTerm.write('    </deliveryTerm>');

    // Документ-основание (акт/накладная) — опционально
    final deliveryDoc = StringBuffer();
    if (invoice.deliveryDocDate != null) {
      deliveryDoc.write(
          '    <deliveryDocDate>${_dateFmt.format(invoice.deliveryDocDate!)}</deliveryDocDate>\n');
    }
    if (invoice.deliveryDocNum != null &&
        invoice.deliveryDocNum!.trim().isNotEmpty) {
      deliveryDoc.write(
          '    <deliveryDocNum>${_esc(invoice.deliveryDocNum!.trim())}</deliveryDocNum>\n');
    }

    final buyerTin = invoice.buyerIin ?? '';

    return '''<v2:invoice xmlns:a="abstractInvoice.esf" xmlns:v2="v2.esf">
    <date>$invoiceDate</date>
    <invoiceType>ORDINARY_INVOICE</invoiceType>
    <num>${_numericNum(invoice.number)}</num>
    <operatorFullname>${_esc(operator)}</operatorFullname>
    <turnoverDate>$turnoverDate</turnoverDate>
    <consignee>
        <address>${_esc(consigneeAddress)}</address>
        <countryCode>KZ</countryCode>
        <name>${_esc(consigneeName)}</name>
        <tin>${_esc(consigneeTin)}</tin>
    </consignee>
    <consignor>
        <address>${_esc(consignorAddress)}</address>
        <name>${_esc(consignorName)}</name>
        <tin>${_esc(consignorTin)}</tin>
    </consignor>
    <customers>
        <customer>
            <address></address>
            <countryCode>KZ</countryCode>
            <name>${_esc(invoice.clientName)}</name>
            <tin>${_esc(buyerTin)}</tin>
        </customer>
    </customers>
${deliveryDoc.toString()}$deliveryTerm
    <productSet>
        <currencyCode>KZT</currencyCode>
        <products>
$products
        </products>
        <totalExciseAmount>0</totalExciseAmount>
        <totalNdsAmount>${_num(totalVat)}</totalNdsAmount>
        <totalPriceWithTax>${_num(totalGross)}</totalPriceWithTax>
        <totalPriceWithoutTax>${_num(totalNet)}</totalPriceWithoutTax>
        <totalTurnoverSize>${_num(totalNet)}</totalTurnoverSize>
    </productSet>
    <sellers>
        <seller>
            <address>${_esc(company.address ?? '')}</address>
            <bank>${_esc(company.bankName ?? '')}</bank>
            <bik>${_esc(company.bik ?? '')}</bik>
            <iik>${_esc(company.iik ?? '')}</iik>
            <kbe>${_esc(company.kbe ?? '19')}</kbe>
            <name>${_esc(company.name)}</name>
            <tin>${_esc(company.iin)}</tin>
        </seller>
    </sellers>
</v2:invoice>''';
  }

  /// Номер ЭСФ (поле `num`) по XSD КГД — строго `[0-9]{1,30}`.
  /// Номер счёта пользователя может быть «СЧ-2026-001» — извлекаем только
  /// цифры. Если цифр нет — fallback на timestamp (тоже число).
  static String _numericNum(String invoiceNumber) {
    final digits = invoiceNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty && digits.length <= 30) return digits;
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  /// Формат чисел как в ИС ЭСФ: точка-разделитель, без разделителей тысяч,
  /// хвостовые нули обрезаются (`1335906.5`, `1`, `0`).
  static String _num(double v) {
    final rounded = (v * 100).round() / 100;
    if (rounded == rounded.truncateToDouble()) {
      return rounded.toInt().toString();
    }
    var s = rounded.toStringAsFixed(2);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  /// XML-экранирование спецсимволов
  static String _esc(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
