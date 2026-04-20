import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class AuthService {
  static const _kToken  = 'auth_token';
  static const _kUserId = 'auth_user_id';
  static const _kEmail  = 'auth_email';

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kToken);
  }

  static Future<bool> isLoggedIn() async => (await getToken()) != null;

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserId);
  }

  static Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEmail);
  }

  static Future<AuthSnapshot> login(String email, String password) async {
    final data = await ApiClient.post('/auth/login', {
      'email': email.trim().toLowerCase(),
      'password': password,
    }) as Map;
    await _persist(data['token'] as String, data['userId'] as String, email.trim().toLowerCase());
    return AuthSnapshot.fromJson(data);
  }

  static Future<AuthSnapshot> register(
      String email, String password, String name) async {
    final data = await ApiClient.post('/auth/register', {
      'email': email.trim().toLowerCase(),
      'password': password,
      'name': name.trim(),
    }) as Map;
    await _persist(data['token'] as String, data['userId'] as String, email.trim().toLowerCase());
    return AuthSnapshot.fromJson(data);
  }

  static Future<AuthSnapshot> me() async {
    final data = await ApiClient.get('/auth/me') as Map;
    return AuthSnapshot.fromJson(data);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kEmail);
  }

  static Future<void> _persist(String token, String userId, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kUserId, userId);
    await prefs.setString(_kEmail, email);
  }
}

class AuthSnapshot {
  final String tier;
  final String? trialStartedAt;
  final String? trialExpiresAt;
  final String? subscriptionExpiresAt;

  const AuthSnapshot({
    required this.tier,
    this.trialStartedAt,
    this.trialExpiresAt,
    this.subscriptionExpiresAt,
  });

  factory AuthSnapshot.fromJson(Map data) => AuthSnapshot(
        tier: data['tier'] as String? ?? 'free',
        trialStartedAt: data['trialStartedAt'] as String?,
        trialExpiresAt: data['trialExpiresAt'] as String?,
        subscriptionExpiresAt: data['subscriptionExpiresAt'] as String?,
      );
}
