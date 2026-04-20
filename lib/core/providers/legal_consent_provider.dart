import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/legal_docs.dart';
import '../services/hive_service.dart';

/// Состояние согласия пользователя с юридическими документами.
/// Хранится локально в Hive (settings box).
class LegalConsentState {
  /// Версия, с которой пользователь согласился. `null` — не согласился ни разу.
  final String? acceptedVersion;

  /// Когда согласился (ISO8601). `null` если не согласился.
  final DateTime? acceptedAt;

  /// Отключён ли пре-экспортный дисклеймер пользователем.
  final bool exportDisclaimerDismissed;

  const LegalConsentState({
    this.acceptedVersion,
    this.acceptedAt,
    this.exportDisclaimerDismissed = false,
  });

  /// Актуально ли согласие с текущей версией документов.
  bool get isCurrent => acceptedVersion == legalDocsVersion;

  LegalConsentState copyWith({
    String? acceptedVersion,
    DateTime? acceptedAt,
    bool? exportDisclaimerDismissed,
  }) {
    return LegalConsentState(
      acceptedVersion: acceptedVersion ?? this.acceptedVersion,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      exportDisclaimerDismissed:
          exportDisclaimerDismissed ?? this.exportDisclaimerDismissed,
    );
  }

  static const empty = LegalConsentState();
}

class LegalConsentNotifier extends StateNotifier<LegalConsentState> {
  LegalConsentNotifier() : super(LegalConsentState.empty) {
    _load();
  }

  static const _versionKey = 'legal_accepted_version';
  static const _atKey = 'legal_accepted_at';
  static const _exportDismissedKey = 'legal_export_dismissed';

  void _load() {
    final box = HiveService.settings;
    final version = box.get(_versionKey) as String?;
    final atStr = box.get(_atKey) as String?;
    final dismissed = box.get(_exportDismissedKey, defaultValue: false) as bool;
    state = LegalConsentState(
      acceptedVersion: version,
      acceptedAt: atStr != null ? DateTime.tryParse(atStr) : null,
      exportDisclaimerDismissed: dismissed,
    );
  }

  /// Пометить, что пользователь согласился с текущей версией.
  Future<void> accept() async {
    final box = HiveService.settings;
    final now = DateTime.now();
    await box.put(_versionKey, legalDocsVersion);
    await box.put(_atKey, now.toIso8601String());
    state = state.copyWith(
      acceptedVersion: legalDocsVersion,
      acceptedAt: now,
    );
  }

  /// Скрыть дисклеймер перед экспортом в дальнейшем.
  Future<void> dismissExportDisclaimer() async {
    final box = HiveService.settings;
    await box.put(_exportDismissedKey, true);
    state = state.copyWith(exportDisclaimerDismissed: true);
  }

  /// Сбросить согласие (например, при выходе из аккаунта).
  Future<void> reset() async {
    final box = HiveService.settings;
    await box.delete(_versionKey);
    await box.delete(_atKey);
    state = LegalConsentState.empty;
  }
}

final legalConsentProvider =
    StateNotifierProvider<LegalConsentNotifier, LegalConsentState>((ref) {
  return LegalConsentNotifier();
});
