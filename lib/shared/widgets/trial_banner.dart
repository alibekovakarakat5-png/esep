/// TrialBanner — sticky banner shown at the top of the dashboard
/// while the user is on a trial. Counts down days, becomes a hard
/// "buy now" call-to-action once trial expires.
///
/// Mirrors the Connect dashboard's TrialBanner so both products feel
/// consistent.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/providers/subscription_provider.dart';
import '../../core/theme/app_theme.dart';

class TrialBanner extends ConsumerWidget {
  const TrialBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider);

    // Don't render if user is already paying.
    if (sub.isSubscriptionActive) return const SizedBox.shrink();

    // No trial info at all (offline/local-only) — hide.
    if (sub.trialExpiresAt == null) return const SizedBox.shrink();

    final daysLeft = sub.trialDaysLeft;
    final expired = !sub.isInTrial;

    // Tone:
    //   expired → red, hard CTA
    //   1-2 days → amber warning
    //   3+ days → blue info
    final Color bg;
    final Color fg;
    final IconData icon;
    final String text;
    final String cta;

    if (expired) {
      bg = EsepColors.expense; // red
      fg = Colors.white;
      icon = Iconsax.warning_2;
      text = 'Пробный период закончился. Подключите тариф чтобы продолжить.';
      cta = 'Оплатить';
    } else if (daysLeft <= 2) {
      bg = EsepColors.warning; // amber
      fg = Colors.white;
      icon = Iconsax.timer_1;
      text = '⚠️ Бесплатный период: осталось $daysLeft ${_plural(daysLeft, 'день', 'дня', 'дней')} — успейте подключить тариф';
      cta = 'Тарифы';
    } else {
      bg = EsepColors.primary; // blue/teal
      fg = Colors.white;
      icon = Iconsax.timer_1;
      text = 'Бесплатный период: осталось $daysLeft ${_plural(daysLeft, 'день', 'дня', 'дней')}';
      cta = 'Тарифы';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () => showPaywall(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: bg,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            child: Text(cta),
          ),
        ],
      ),
    );
  }

  static String _plural(int n, String one, String few, String many) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return few;
    return many;
  }
}

/// Full-screen paywall shown when user tries an action that requires
/// an active subscription (and trial has expired).
///
/// Use via `showHardPaywall(context)` from any place that needs to
/// stop a free user dead in their tracks.
class HardPaywallScreen extends StatelessWidget {
  const HardPaywallScreen({super.key, this.feature});
  final String? feature;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подписка'),
        leading: IconButton(
          icon: const Icon(Iconsax.close_square),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 96, height: 96,
                  margin: const EdgeInsets.symmetric(horizontal: 120),
                  decoration: BoxDecoration(
                    color: EsepColors.expense.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Iconsax.lock_1, size: 48, color: EsepColors.expense),
                ),
                const SizedBox(height: 24),
                Text(
                  feature != null ? 'Для "$feature" нужна подписка' : 'Пробный период закончился',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: EsepColors.textPrimary),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Чтобы продолжить пользоваться Esep — подключите тариф.\n7 дней бесплатно вы уже получили.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: EsepColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  icon: const Icon(Iconsax.crown_1),
                  label: const Text('Посмотреть тарифы', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    showPaywall(context, feature: feature);
                  },
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Позже', style: TextStyle(color: EsepColors.textSecondary)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Show the hard paywall as a full-screen modal. Returns true if the
/// user clicked "посмотреть тарифы" (so caller can decide whether to
/// proceed when control returns).
Future<void> showHardPaywall(BuildContext context, {String? feature}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => HardPaywallScreen(feature: feature),
    ),
  );
}

/// Convenience guard: call this BEFORE any premium action. Returns
/// true if the user has access (paying OR in active trial). Returns
/// false and shows the paywall when the user is locked out.
bool ensureSubscriptionOrPaywall(BuildContext context, WidgetRef ref, {String? feature}) {
  final sub = ref.read(subscriptionProvider);
  if (sub.hasFullAccess) return true;
  showHardPaywall(context, feature: feature);
  return false;
}
