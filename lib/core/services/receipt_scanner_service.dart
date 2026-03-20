import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Parsed receipt data from OCR
class ReceiptData {
  final double? totalAmount;
  final String? storeName;
  final DateTime? date;
  final List<String> rawLines;

  const ReceiptData({
    this.totalAmount,
    this.storeName,
    this.date,
    this.rawLines = const [],
  });
}

class ReceiptScannerService {
  ReceiptScannerService._();

  static final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Scan receipt image and extract data
  static Future<ReceiptData> scanReceipt(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognized = await _textRecognizer.processImage(inputImage);

    final lines = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        lines.add(line.text);
      }
    }

    return ReceiptData(
      totalAmount: _extractTotal(lines),
      storeName: _extractStoreName(lines),
      date: _extractDate(lines),
      rawLines: lines,
    );
  }

  /// Extract total amount from receipt lines
  static double? _extractTotal(List<String> lines) {
    // Common patterns on KZ receipts
    final totalPatterns = [
      RegExp(r'(?:ИТОГО|ИТОГ|итого|Итого|TOTAL|Total|ВСЕГО|Всего)[:\s]*[=]?\s*([\d\s,.]+)', caseSensitive: false),
      RegExp(r'(?:К ОПЛАТЕ|к оплате|СУММА|Сумма|SUM)[:\s]*[=]?\s*([\d\s,.]+)', caseSensitive: false),
      RegExp(r'(?:ОПЛАТА|оплата|ОПЛАЧЕНО)[:\s]*[=]?\s*([\d\s,.]+)', caseSensitive: false),
    ];

    // Search from bottom up (total is usually at the bottom)
    for (final line in lines.reversed) {
      for (final pattern in totalPatterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          final amountStr = match.group(1)!
              .replaceAll(RegExp(r'\s'), '')
              .replaceAll(',', '.');
          final amount = double.tryParse(amountStr);
          if (amount != null && amount > 0 && amount < 100000000) {
            return amount;
          }
        }
      }
    }

    // Fallback: find the largest number that looks like a total
    double? largest;
    for (final line in lines.reversed.take(10)) {
      final amounts = RegExp(r'(\d[\d\s]*[.,]\d{2})').allMatches(line);
      for (final m in amounts) {
        final val = double.tryParse(
            m.group(1)!.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));
        if (val != null && val > 0 && (largest == null || val > largest)) {
          largest = val;
        }
      }
    }
    return largest;
  }

  /// Extract store name (usually first non-empty meaningful line)
  static String? _extractStoreName(List<String> lines) {
    final skipPatterns = [
      RegExp(r'^\d{10,}'), // BIN/IIN numbers
      RegExp(r'^(ИИН|БИН|BIN|IIN)', caseSensitive: false),
      RegExp(r'^\d{2}[./]\d{2}[./]\d{2,4}'), // dates
      RegExp(r'^(чек|ЧЕК|ФИСКАЛЬНЫЙ|фискальный|Кассовый)', caseSensitive: false),
      RegExp(r'^\s*$'), // empty
      RegExp(r'^[-=*_]+$'), // separators
    ];

    for (final line in lines.take(5)) {
      final trimmed = line.trim();
      if (trimmed.length < 3) continue;
      bool skip = false;
      for (final p in skipPatterns) {
        if (p.hasMatch(trimmed)) {
          skip = true;
          break;
        }
      }
      if (!skip) return trimmed;
    }
    return null;
  }

  /// Extract date from receipt
  static DateTime? _extractDate(List<String> lines) {
    final datePatterns = [
      // DD.MM.YYYY or DD/MM/YYYY
      RegExp(r'(\d{2})[./](\d{2})[./](\d{4})'),
      // DD.MM.YY
      RegExp(r'(\d{2})[./](\d{2})[./](\d{2})\b'),
    ];

    for (final line in lines) {
      for (final pattern in datePatterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          final day = int.tryParse(match.group(1)!);
          final month = int.tryParse(match.group(2)!);
          var year = int.tryParse(match.group(3)!);
          if (day == null || month == null || year == null) continue;
          if (year < 100) year += 2000;
          if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
            try {
              return DateTime(year, month, day);
            } catch (_) {
              continue;
            }
          }
        }
      }
    }
    return null;
  }

  static void dispose() {
    _textRecognizer.close();
  }
}
