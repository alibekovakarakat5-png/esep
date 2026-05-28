import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class AuthService {
  static const _kToken       = 'auth_token';
  static const _kUserId      = 'auth_user_id';
  static const _kEmail       = 'auth_email';
  // Признак «бета-тестировщик» — кешируется, чтобы кнопка появлялась
  // мгновенно при запуске, без ожидания /auth/me запроса.
  static const _kBetaTester  = 'auth_is_beta_tester';
  // Флаг impersonation — true когда токен получен из админки.
  static const _kImpersonated = 'auth_is_impersonated';

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kToken);
  }

  static Future<bool> isLoggedIn() async => (await getToken()) != null;

  /// Кешированный флаг «вошёл из админки под клиента». Используется баннером.
  static Future<bool> isImpersonated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kImpersonated) ?? false;
  }

  /// Принять токен impersonation (передан из админки через URL).
  /// Очищает любую предыдущую сессию и сохраняет новую.
  static Future<void> acceptImpersonationToken(String token, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kEmail, email);
    await prefs.setBool(_kImpersonated, true);
    await prefs.remove(_kUserId); // подтянется через /me
    await prefs.setBool(_kBetaTester, false);
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserId);
  }

  static Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEmail);
  }

  /// Кешированный флаг бета-тестировщика. true только если /auth/me
  /// последний раз вернул isBetaTester=true. Безопасное умолчание — false.
  static Future<bool> isBetaTester() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBetaTester) ?? false;
  }

  static Future<AuthSnapshot> login(String email, String password) async {
    final data = await ApiClient.post('/auth/login', {
      'email': email.trim().toLowerCase(),
      'password': password,
    }) as Map;
    final snap = AuthSnapshot.fromJson(data);
    await _persist(data['token'] as String, data['userId'] as String, email.trim().toLowerCase(), snap.isBetaTester);
    return snap;
  }

  static Future<AuthSnapshot> register(
    String email, String password, String name, {
    String? phone,
  }) async {
    final body = <String, dynamic>{
      'email': email.trim().toLowerCase(),
      'password': password,
      'name': name.trim(),
    };
    if (phone != null && phone.trim().isNotEmpty) {
      body['phone'] = phone.trim();
    }
    final data = await ApiClient.post('/auth/register', body) as Map;
    final snap = AuthSnapshot.fromJson(data);
    await _persist(data['token'] as String, data['userId'] as String, email.trim().toLowerCase(), snap.isBetaTester);
    return snap;
  }

  static Future<AuthSnapshot> me() async {
    final data = await ApiClient.get('/auth/me') as Map;
    final snap = AuthSnapshot.fromJson(data);
    // Обновляем кеш при каждом /me — если админ переключил тумблер,
    // флаг подтянется при следующем заходе в приложение.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBetaTester, snap.isBetaTester);
    return snap;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kEmail);
    await prefs.remove(_kBetaTester);
    await prefs.remove(_kImpersonated);
  }

  static Future<void> _persist(String token, String userId, String email, bool isBetaTester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kUserId, userId);
    await prefs.setString(_kEmail, email);
    await prefs.setBool(_kBetaTester, isBetaTester);
  }
}

class AuthSnapshot {
  final String tier;
  final String? trialStartedAt;
  final String? trialExpiresAt;
  final String? subscriptionExpiresAt;
  final bool isBetaTester;
  final bool isImpersonated;

  const AuthSnapshot({
    required this.tier,
    this.trialStartedAt,
    this.trialExpiresAt,
    this.subscriptionExpiresAt,
    this.isBetaTester = false,
    this.isImpersonated = false,
  });

  factory AuthSnapshot.fromJson(Map data) => AuthSnapshot(
        tier: data['tier'] as String? ?? 'free',
        trialStartedAt: data['trialStartedAt'] as String?,
        trialExpiresAt: data['trialExpiresAt'] as String?,
        subscriptionExpiresAt: data['subscriptionExpiresAt'] as String?,
        isBetaTester: data['isBetaTester'] as bool? ?? false,
        isImpersonated: data['isImpersonated'] as bool? ?? false,
      );
}
