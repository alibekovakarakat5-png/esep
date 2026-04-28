import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tax_profile.dart';
import '../services/api_client.dart';

/// Загружает профиль из бэкенда. Возвращает дефолтный, если ещё не сохранён.
class TaxProfileNotifier extends StateNotifier<AsyncValue<TaxProfile>> {
  TaxProfileNotifier() : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final j = await ApiClient.get('/tax-profile') as Map<String, dynamic>;
      state = AsyncValue.data(TaxProfile.fromJson(j));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> save(TaxProfile profile) async {
    try {
      final j = await ApiClient.put('/tax-profile', profile.toJson())
          as Map<String, dynamic>;
      state = AsyncValue.data(TaxProfile.fromJson(j));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final taxProfileProvider =
    StateNotifierProvider<TaxProfileNotifier, AsyncValue<TaxProfile>>(
  (ref) => TaxProfileNotifier(),
);
