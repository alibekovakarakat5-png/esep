import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class AuthService {
  static const _kToken  = 'auth_token';
  static const _kUserId = 'auth_user_id';

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kToken);
  }

  static Future<bool> isLoggedIn() async => (await getToken()) != null;

  static Future<void> login(String email, String password) async {
    final data = await ApiClient.post('/auth/login', {
      'email': email.trim().toLowerCase(),
      'password': password,
    }) as Map;
    await _persist(data['token'] as String, data['userId'] as String);
  }

  static Future<void> register(
      String email, String password, String name) async {
    final data = await ApiClient.post('/auth/register', {
      'email': email.trim().toLowerCase(),
      'password': password,
      'name': name.trim(),
    }) as Map;
    await _persist(data['token'] as String, data['userId'] as String);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
  }

  static Future<void> _persist(String token, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kUserId, userId);
  }
}
