import '../models/tax_profile.dart';
import 'api_client.dart';

/// КБК с метаданными.
class KbkItem {
  final String code;
  final String label;
  final String fullName;
  final String paymentType;
  final String? note;
  final String? lawRef;
  final String? payerRole;

  const KbkItem({
    required this.code,
    required this.label,
    required this.fullName,
    required this.paymentType,
    this.note,
    this.lawRef,
    this.payerRole,
  });

  factory KbkItem.fromJson(Map<String, dynamic> j) => KbkItem(
        code: (j['code'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        fullName: (j['full_name'] ?? '') as String,
        paymentType: (j['payment_type'] ?? '') as String,
        note: j['note'] as String?,
        lawRef: j['law_ref'] as String?,
        payerRole: j['payer_role'] as String?,
      );
}

class KbkRecommendation {
  final KbkItem? recommended;
  final List<KbkItem> alternatives;
  final String reason;

  const KbkRecommendation({
    required this.recommended,
    required this.alternatives,
    required this.reason,
  });

  factory KbkRecommendation.fromJson(Map<String, dynamic> j) => KbkRecommendation(
        recommended: j['recommended'] is Map<String, dynamic>
            ? KbkItem.fromJson(j['recommended'] as Map<String, dynamic>)
            : null,
        alternatives: (j['alternatives'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(KbkItem.fromJson)
            .toList(),
        reason: (j['reason'] ?? '') as String,
      );
}

class KbkValidation {
  final bool ok;
  final String level;     // 'ok' | 'warn' | 'red'
  final String message;
  final KbkItem? expected;

  const KbkValidation({
    required this.ok,
    required this.level,
    required this.message,
    this.expected,
  });

  factory KbkValidation.fromJson(Map<String, dynamic> j) => KbkValidation(
        ok: (j['ok'] as bool?) ?? false,
        level: (j['level'] ?? 'warn') as String,
        message: (j['message'] ?? '') as String,
        expected: j['expected'] is Map<String, dynamic>
            ? KbkItem.fromJson(j['expected'] as Map<String, dynamic>)
            : null,
      );
}

class PaymentTypeOption {
  final String id;
  final String label;
  const PaymentTypeOption(this.id, this.label);

  factory PaymentTypeOption.fromJson(Map<String, dynamic> j) =>
      PaymentTypeOption((j['id'] ?? '') as String, (j['label'] ?? '') as String);
}

class KbkService {
  KbkService._();

  /// Кеш в рамках сессии.
  static List<KbkItem>? _cachedAll;
  static List<PaymentTypeOption>? _cachedTypes;

  static Future<List<KbkItem>> listAll() async {
    if (_cachedAll != null) return _cachedAll!;
    final list = await ApiClient.get('/kbk/list') as List;
    _cachedAll = list
        .whereType<Map<String, dynamic>>()
        .map(KbkItem.fromJson)
        .toList();
    return _cachedAll!;
  }

  static Future<List<PaymentTypeOption>> listPaymentTypes() async {
    if (_cachedTypes != null) return _cachedTypes!;
    final list = await ApiClient.get('/kbk/payment-types') as List;
    _cachedTypes = list
        .whereType<Map<String, dynamic>>()
        .map(PaymentTypeOption.fromJson)
        .toList();
    return _cachedTypes!;
  }

  static Future<KbkRecommendation> recommend({
    required TaxProfile profile,
    required String paymentType,
  }) async {
    final j = await ApiClient.post('/kbk/recommend', {
      'profile':      profile.toJson(),
      'payment_type': paymentType,
    }) as Map<String, dynamic>;
    return KbkRecommendation.fromJson(j);
  }

  static Future<KbkValidation> validate({
    required TaxProfile profile,
    required String code,
    String? paymentType,
  }) async {
    final j = await ApiClient.post('/kbk/validate', {
      'profile': profile.toJson(),
      'code':    code,
      if (paymentType != null) 'payment_type': paymentType,
    }) as Map<String, dynamic>;
    return KbkValidation.fromJson(j);
  }

  /// КБК для текущего пользователя (фильтр по профилю на бэке).
  static Future<List<KbkItem>> forMe() async {
    final j = await ApiClient.get('/kbk/for-me') as Map<String, dynamic>;
    final items = j['items'] as List? ?? [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(KbkItem.fromJson)
        .toList();
  }
}
