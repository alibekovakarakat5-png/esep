/// Сервис для работы с Esep Platform API (enterprise клиенты).
///
/// Особенность: для большинства методов используется JWT-аутентификация
/// (как у обычного юзера), потому что enterprise-юзер логинится в Esep так же
/// как обычный. Серверный endpoint `/api/platform/my-account` возвращает
/// API-ключ и набор фич — он используется для дальнейших test-запросов.
///
/// Для test-вызовов сервисов (например, кнопка "Попробовать" в дашборде)
/// используется X-Platform-Key, выданный юзеру.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'auth_service.dart';

class PlatformApiService {
  /// Данные платформенного аккаунта текущего залогиненного юзера.
  /// Возвращает null если юзер не enterprise.
  static Future<PlatformAccount?> myAccount() async {
    try {
      final data = await ApiClient.get('/platform/my-account');
      if (data['has_platform_access'] != true) return null;
      return PlatformAccount.fromJson(data);
    } catch (e) {
      // 403 — нет доступа
      return null;
    }
  }

  /// Валидация ИИН — алгоритмическая проверка.
  static Future<Map<String, dynamic>> validateIin(String iin, String apiKey) async {
    final url = Uri.parse('${ApiClient.baseUrl}/platform/iin/validate/$iin');
    final resp = await http.get(url, headers: {
      'X-Platform-Key': apiKey,
      'Accept': 'application/json',
    });
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Информация о налогоплательщике по БИН/ИИН (stat.gov.kz + fallback).
  static Future<Map<String, dynamic>> taxpayerInfo(String bin, String apiKey) async {
    final url = Uri.parse('${ApiClient.baseUrl}/platform/taxpayer/$bin');
    final resp = await http.get(url, headers: {
      'X-Platform-Key': apiKey,
      'Accept': 'application/json',
    });
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Текущее состояние месячного лимита 300 МРП для самозанятого.
  static Future<Map<String, dynamic>> incomeLimitStatus(String iin, String apiKey) async {
    final url = Uri.parse('${ApiClient.baseUrl}/platform/income-limit/status/$iin');
    final resp = await http.get(url, headers: {
      'X-Platform-Key': apiKey,
      'Accept': 'application/json',
    });
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// MAGIC endpoint: всё в одном вызове.
  static Future<Map<String, dynamic>> processPayment({
    required String courierIin,
    required double amount,
    required String orderId,
    required String apiKey,
    String paymentMethod = 'card',
    bool skipTaxpayerCheck = false,
  }) async {
    final url = Uri.parse('${ApiClient.baseUrl}/platform/process-payment');
    final resp = await http.post(
      url,
      headers: {
        'X-Platform-Key': apiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'courier_iin': courierIin,
        'amount': amount,
        'order_id': orderId,
        'payment_method': paymentMethod,
        'skip_taxpayer_check': skipTaxpayerCheck,
      }),
    );
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Отмена заказа.
  static Future<Map<String, dynamic>> cancelOrder({
    required String orderId,
    required String apiKey,
    String? reason,
  }) async {
    final url = Uri.parse('${ApiClient.baseUrl}/platform/cancel-order');
    final resp = await http.post(
      url,
      headers: {
        'X-Platform-Key': apiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'order_id': orderId,
        'reason': reason ?? 'Отменено через дашборд Esep',
      }),
    );
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}

/// Снимок платформенного аккаунта (что вернул GET /platform/my-account).
class PlatformAccount {
  final String apiKey;
  final String clientName;
  final String? clientBin;
  final String tier;
  final List<String> features;
  final int monthlyQuota;
  final int requestsThisMonth;
  final int requestsTotal;
  final ReceiptsStats receipts;
  final String apiBaseUrl;

  PlatformAccount({
    required this.apiKey,
    required this.clientName,
    required this.clientBin,
    required this.tier,
    required this.features,
    required this.monthlyQuota,
    required this.requestsThisMonth,
    required this.requestsTotal,
    required this.receipts,
    required this.apiBaseUrl,
  });

  factory PlatformAccount.fromJson(Map<String, dynamic> json) {
    return PlatformAccount(
      apiKey: json['api_key'] as String,
      clientName: json['client_name'] as String? ?? '',
      clientBin: json['client_bin'] as String?,
      tier: json['tier'] as String? ?? 'enterprise',
      features: (json['features'] as List?)?.cast<String>() ?? const [],
      monthlyQuota: (json['monthly_quota'] as num?)?.toInt() ?? 0,
      requestsThisMonth: (json['requests_this_month'] as num?)?.toInt() ?? 0,
      requestsTotal: (json['requests_total'] as num?)?.toInt() ?? 0,
      receipts: ReceiptsStats.fromJson(json['receipts'] as Map<String, dynamic>? ?? {}),
      apiBaseUrl: json['api_base_url'] as String? ?? '',
    );
  }

  bool hasFeature(String code) => features.contains(code);
}

class ReceiptsStats {
  final int issued;       // фискализированы курьером
  final int awaiting;     // загружены, ждут курьера
  final int cancelled;
  final int pending;      // в очереди (нет договора ОФД)
  final int failed;
  final double totalAmount;

  ReceiptsStats({
    required this.issued,
    required this.awaiting,
    required this.cancelled,
    required this.pending,
    required this.failed,
    required this.totalAmount,
  });

  factory ReceiptsStats.fromJson(Map<String, dynamic> json) {
    return ReceiptsStats(
      issued: (json['issued'] as num?)?.toInt() ?? 0,
      awaiting: (json['awaiting'] as num?)?.toInt() ?? 0,
      cancelled: (json['cancelled'] as num?)?.toInt() ?? 0,
      pending: (json['pending'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  int get total => issued + awaiting + cancelled + pending + failed;
}
