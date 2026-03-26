import 'api_client.dart';

class PromoService {
  /// Validate promo code without activating
  static Future<PromoResult> validate(String code) async {
    try {
      final data = await ApiClient.post('/promos/validate', {'code': code}) as Map;
      return PromoResult(
        valid: true,
        tier: data['tier'] as String? ?? 'ip',
        durationDays: data['duration_days'] as int? ?? 30,
        description: data['description'] as String? ?? '',
      );
    } on ApiException catch (e) {
      return PromoResult(valid: false, error: e.message);
    }
  }

  /// Activate promo code — upgrades user tier on server
  static Future<PromoActivation> activate(String code) async {
    try {
      final data = await ApiClient.post('/promos/activate', {'code': code}) as Map;
      return PromoActivation(
        success: true,
        tier: data['tier'] as String? ?? 'ip',
        durationDays: data['duration_days'] as int? ?? 30,
        expiresAt: data['expires_at'] as String? ?? '',
        message: data['message'] as String? ?? 'Промокод активирован!',
      );
    } on ApiException catch (e) {
      return PromoActivation(success: false, error: e.message);
    }
  }
}

class PromoResult {
  final bool valid;
  final String? tier;
  final int? durationDays;
  final String? description;
  final String? error;

  const PromoResult({
    required this.valid,
    this.tier,
    this.durationDays,
    this.description,
    this.error,
  });
}

class PromoActivation {
  final bool success;
  final String? tier;
  final int? durationDays;
  final String? expiresAt;
  final String? message;
  final String? error;

  const PromoActivation({
    required this.success,
    this.tier,
    this.durationDays,
    this.expiresAt,
    this.message,
    this.error,
  });
}
