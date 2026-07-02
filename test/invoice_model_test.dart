// Раунд-трип модели Invoice: toJson → fromJson без потерь.
// Формат JSON — контракт с сервером (server/src/routes/invoices.js):
// сервер принимает toJson() как есть и отдаёт GET в этом же snake_case виде.
//
// Запуск: flutter test test/invoice_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:esep/core/models/invoice.dart';

void main() {
  group('Invoice JSON round-trip', () {
    test('полный счёт с оплатой и ЭСФ-реквизитами', () {
      final src = Invoice(
        id: 'inv-1',
        number: 'СЧ-2026-001',
        clientId: 'cl-1',
        clientName: 'ТОО Клиент',
        buyerIin: '123456789012',
        items: const [
          InvoiceItem(
            id: 'it-1',
            description: 'Подписка Esep · июль',
            quantity: 1,
            unitPrice: 50000,
            unitCode: '931',
            unitName: 'услуга',
            esfUnitCode: '5114',
          ),
        ],
        status: InvoiceStatus.sent,
        createdAt: DateTime(2026, 7, 2, 10, 30),
        dueDate: DateTime(2026, 7, 10),
        notes: 'Оплата до 10 числа',
        paymentLink: 'https://pay.kaspi.kz/pay/abc123',
        contractNum: 'Д-7',
        contractDate: DateTime(2026, 7, 1),
      );

      final restored = Invoice.fromJson(src.toJson());

      expect(restored.id, src.id);
      expect(restored.number, src.number);
      expect(restored.clientName, src.clientName);
      expect(restored.buyerIin, src.buyerIin);
      expect(restored.paymentLink, src.paymentLink);
      expect(restored.status, InvoiceStatus.sent);
      expect(restored.dueDate, DateTime(2026, 7, 10));
      expect(restored.notes, src.notes);
      expect(restored.contractNum, 'Д-7');
      expect(restored.contractDate, DateTime(2026, 7, 1));
      expect(restored.items.single.unitPrice, 50000);
      expect(restored.items.single.unitCode, '931');
      expect(restored.items.single.unitName, 'услуга');
      expect(restored.items.single.esfUnitCode, '5114');
      expect(restored.totalAmount, 50000);
    });

    test('минимальный счёт без опциональных полей', () {
      final src = Invoice(
        id: 'inv-2',
        number: 'СЧ-2026-002',
        clientName: 'ИП Минимал',
        items: const [
          InvoiceItem(id: 'it-2', description: 'Услуга', quantity: 2, unitPrice: 1500),
        ],
        status: InvoiceStatus.draft,
        createdAt: DateTime(2026, 7, 2),
      );

      final json = src.toJson();
      expect(json.containsKey('payment_link'), isFalse);
      expect(json.containsKey('buyer_iin'), isFalse);

      final restored = Invoice.fromJson(json);
      expect(restored.paymentLink, isNull);
      expect(restored.buyerIin, isNull);
      expect(restored.dueDate, isNull);
      expect(restored.totalAmount, 3000);
    });

    test('copyWith сохраняет paymentLink', () {
      final src = Invoice(
        id: 'inv-3',
        number: 'СЧ-2026-003',
        clientName: 'ТОО К',
        items: const [
          InvoiceItem(id: 'it-3', description: 'X', quantity: 1, unitPrice: 100),
        ],
        status: InvoiceStatus.draft,
        createdAt: DateTime(2026, 7, 2),
        paymentLink: 'https://pay.kaspi.kz/pay/xyz',
      );
      final copy = src.copyWith(status: InvoiceStatus.paid);
      expect(copy.paymentLink, 'https://pay.kaspi.kz/pay/xyz');
      expect(copy.status, InvoiceStatus.paid);
    });
  });
}
