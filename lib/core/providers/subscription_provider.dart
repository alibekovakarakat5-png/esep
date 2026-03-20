import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

// ── Subscription tiers ──────────────────────────────────────────────────────

enum SubscriptionTier { free, solo, accountant, accountantPro }

extension SubscriptionTierExt on SubscriptionTier {
  String get label {
    switch (this) {
      case SubscriptionTier.free: return 'Бесплатный';
      case SubscriptionTier.solo: return 'Solo';
      case SubscriptionTier.accountant: return 'Бухгалтер';
      case SubscriptionTier.accountantPro: return 'Бухгалтер Про';
    }
  }

  /// Monthly price in KZT
  int get monthlyPrice {
    switch (this) {
      case SubscriptionTier.free: return 0;
      case SubscriptionTier.solo: return 1900;
      case SubscriptionTier.accountant: return 4900;
      case SubscriptionTier.accountantPro: return 14900;
    }
  }

  /// Yearly price in KZT (2 months free)
  int get yearlyPrice {
    switch (this) {
      case SubscriptionTier.free: return 0;
      case SubscriptionTier.solo: return 18900;
      case SubscriptionTier.accountant: return 48900;
      case SubscriptionTier.accountantPro: return 148900;
    }
  }

  /// Max transactions per month (-1 = unlimited)
  int get maxTransactionsPerMonth {
    switch (this) {
      case SubscriptionTier.free: return 10;
      case SubscriptionTier.solo: return -1;
      case SubscriptionTier.accountant: return -1;
      case SubscriptionTier.accountantPro: return -1;
    }
  }

  /// Max invoices (-1 = unlimited)
  int get maxInvoices {
    switch (this) {
      case SubscriptionTier.free: return 3;
      case SubscriptionTier.solo: return -1;
      case SubscriptionTier.accountant: return -1;
      case SubscriptionTier.accountantPro: return -1;
    }
  }

  /// Max business entities (clients for accountant)
  int get maxBusinessSlots {
    switch (this) {
      case SubscriptionTier.free: return 1;
      case SubscriptionTier.solo: return 1;
      case SubscriptionTier.accountant: return 15;
      case SubscriptionTier.accountantPro: return 50;
    }
  }

  /// BIN lookups per day (-1 = unlimited)
  int get maxBinLookupsPerDay {
    switch (this) {
      case SubscriptionTier.free: return 5;
      case SubscriptionTier.solo: return -1;
      case SubscriptionTier.accountant: return -1;
      case SubscriptionTier.accountantPro: return -1;
    }
  }

  /// Price per extra business slot above limit (KZT/month)
  static const int overflowSlotPrice = 500;

  bool get hasPdfInvoices => this != SubscriptionTier.free;
  bool get hasBankImport => this != SubscriptionTier.free;
  bool get hasAccountantMode =>
      this == SubscriptionTier.accountant ||
      this == SubscriptionTier.accountantPro;
  bool get hasPrioritySupport => this == SubscriptionTier.accountantPro;
  bool get hasTelegramAlerts => this != SubscriptionTier.free;
  bool get hasSalaryCalculator => true; // all tiers
  bool get hasTooCalculator => true;    // all tiers

  String get shortFeatures {
    switch (this) {
      case SubscriptionTier.free:
        return '10 операций/мес, 3 счёта без PDF';
      case SubscriptionTier.solo:
        return 'Безлимит + PDF + импорт банка';
      case SubscriptionTier.accountant:
        return 'До 15 клиентов + ЛПР + дедлайны';
      case SubscriptionTier.accountantPro:
        return 'До 50 клиентов + приоритетная поддержка';
    }
  }
}

// ── Subscription state ──────────────────────────────────────────────────────

class SubscriptionState {
  final SubscriptionTier tier;
  final bool isYearly;
  final DateTime? trialStartedAt;
  final bool trialExpired;
  final int extraSlots; // overflow business slots purchased

  const SubscriptionState({
    this.tier = SubscriptionTier.free,
    this.isYearly = false,
    this.trialStartedAt,
    this.trialExpired = false,
    this.extraSlots = 0,
  });

  bool get isInTrial {
    if (trialStartedAt == null || trialExpired) return false;
    return DateTime.now().difference(trialStartedAt!).inDays < 3;
  }

  bool get hasFullAccess => tier != SubscriptionTier.free || isInTrial;

  int get trialDaysLeft {
    if (trialStartedAt == null) return 3;
    final left = 3 - DateTime.now().difference(trialStartedAt!).inDays;
    return left.clamp(0, 3);
  }

  int get totalBusinessSlots => tier.maxBusinessSlots + extraSlots;

  /// Total monthly cost including overflow slots
  int get effectiveMonthlyPrice =>
      tier.monthlyPrice + (extraSlots * SubscriptionTierExt.overflowSlotPrice);
}

// ── Provider ────────────────────────────────────────────────────────────────

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  SubscriptionNotifier() : super(const SubscriptionState()) {
    _load();
  }

  static const _boxName = 'settings';

  void _load() {
    final box = Hive.box(_boxName);
    final tierStr = box.get('sub_tier', defaultValue: 'free') as String;
    final trialStr = box.get('trial_started') as String?;

    final tier = SubscriptionTier.values.firstWhere(
      (t) => t.name == tierStr,
      orElse: () => SubscriptionTier.free,
    );
    final trialStarted = trialStr != null ? DateTime.tryParse(trialStr) : null;
    final expired = box.get('trial_expired', defaultValue: false) as bool;
    final yearly = box.get('sub_yearly', defaultValue: false) as bool;
    final extras = box.get('sub_extra_slots', defaultValue: 0) as int;

    state = SubscriptionState(
      tier: tier,
      isYearly: yearly,
      trialStartedAt: trialStarted,
      trialExpired: expired,
      extraSlots: extras,
    );
  }

  /// Start 3-day trial (called on first registration)
  void startTrial() {
    if (state.trialStartedAt != null) return;
    final now = DateTime.now();
    Hive.box(_boxName).put('trial_started', now.toIso8601String());
    state = SubscriptionState(
      tier: state.tier,
      isYearly: state.isYearly,
      trialStartedAt: now,
      trialExpired: false,
      extraSlots: state.extraSlots,
    );
  }

  /// Upgrade tier (after payment confirmation)
  void setTier(SubscriptionTier tier, {bool yearly = false}) {
    final box = Hive.box(_boxName);
    box.put('sub_tier', tier.name);
    box.put('sub_yearly', yearly);
    state = SubscriptionState(
      tier: tier,
      isYearly: yearly,
      trialStartedAt: state.trialStartedAt,
      trialExpired: state.trialExpired,
      extraSlots: state.extraSlots,
    );
  }

  /// Add extra business slots (+500 ₸ each)
  void addExtraSlots(int count) {
    final newExtras = state.extraSlots + count;
    Hive.box(_boxName).put('sub_extra_slots', newExtras);
    state = SubscriptionState(
      tier: state.tier,
      isYearly: state.isYearly,
      trialStartedAt: state.trialStartedAt,
      trialExpired: state.trialExpired,
      extraSlots: newExtras,
    );
  }

  /// Check and expire trial
  void checkTrial() {
    if (state.trialStartedAt == null || state.trialExpired) return;
    if (DateTime.now().difference(state.trialStartedAt!).inDays >= 3) {
      Hive.box(_boxName).put('trial_expired', true);
      state = SubscriptionState(
        tier: state.tier,
        isYearly: state.isYearly,
        trialStartedAt: state.trialStartedAt,
        trialExpired: true,
        extraSlots: state.extraSlots,
      );
    }
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>(
        (ref) => SubscriptionNotifier());

// ── Limit check helpers ─────────────────────────────────────────────────────

/// Returns true if the user can add more transactions this month.
/// [currentCount] — number of transactions already recorded this month.
bool canAddTransaction(SubscriptionState sub, int currentCount) {
  if (sub.hasFullAccess) return true;
  final limit = sub.tier.maxTransactionsPerMonth;
  return limit == -1 || currentCount < limit;
}

/// Returns true if the user can create more invoices.
bool canAddInvoice(SubscriptionState sub, int currentCount) {
  if (sub.hasFullAccess) return true;
  final limit = sub.tier.maxInvoices;
  return limit == -1 || currentCount < limit;
}

/// Returns true if BIN lookups are available today.
bool canUseBinLookup(SubscriptionState sub, int todayCount) {
  if (sub.hasFullAccess) return true;
  final limit = sub.tier.maxBinLookupsPerDay;
  return limit == -1 || todayCount < limit;
}

// ── Paywall bottom sheet ────────────────────────────────────────────────────

Future<void> showPaywall(BuildContext context, {String? feature}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _PaywallSheet(feature: feature),
  );
}

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet({this.feature});
  final String? feature;

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  bool _yearly = true; // default to yearly (better value)
  SubscriptionTier _selectedTier = SubscriptionTier.solo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 16, 24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: EsepColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Crown icon
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: EsepColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Iconsax.crown_1, color: EsepColors.primary, size: 36),
          ),
          const SizedBox(height: 20),

          Text(
            widget.feature != null
                ? 'Для "${widget.feature}" нужна подписка'
                : 'Перейдите на платный план',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w800,
              color: EsepColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Безлимит операций, PDF-счета, импорт из банка,\nнапоминания о дедлайнах и многое другое.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: EsepColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 20),

          // Yearly / Monthly toggle
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: EsepColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              _ToggleTab(
                label: 'Годовой',
                badge: '-17%',
                selected: _yearly,
                onTap: () => setState(() => _yearly = true),
              ),
              _ToggleTab(
                label: 'Месячный',
                selected: !_yearly,
                onTap: () => setState(() => _yearly = false),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Plan cards
          _PlanCard(
            tier: SubscriptionTier.solo,
            yearly: _yearly,
            highlighted: _selectedTier == SubscriptionTier.solo,
            badge: 'Популярный',
            onTap: () => setState(() => _selectedTier = SubscriptionTier.solo),
          ),
          const SizedBox(height: 10),
          _PlanCard(
            tier: SubscriptionTier.accountant,
            yearly: _yearly,
            highlighted: _selectedTier == SubscriptionTier.accountant,
            onTap: () => setState(() => _selectedTier = SubscriptionTier.accountant),
          ),
          const SizedBox(height: 10),
          _PlanCard(
            tier: SubscriptionTier.accountantPro,
            yearly: _yearly,
            highlighted: _selectedTier == SubscriptionTier.accountantPro,
            badge: 'Макс',
            onTap: () => setState(() => _selectedTier = SubscriptionTier.accountantPro),
          ),
          const SizedBox(height: 8),

          // Overflow hint
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: EsepColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Iconsax.add_circle, size: 16, color: EsepColors.warning),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Нужно больше? +500 ₸/мес за каждый дополнительный бизнес',
                  style: TextStyle(fontSize: 12, color: EsepColors.textSecondary),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // CTA — WhatsApp / Telegram
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Iconsax.message, size: 18),
              label: const Text('Оформить подписку',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                Navigator.pop(context);
                final price = _yearly
                    ? _selectedTier.yearlyPrice
                    : _selectedTier.monthlyPrice;
                final period = _yearly ? 'год' : 'мес';
                final msg = Uri.encodeComponent(
                  'Здравствуйте! Хочу подключить тариф '
                  '${_selectedTier.label} ($price ₸/$period) в Esep.',
                );
                launchUrl(
                  Uri.parse('https://wa.me/77075884651?text=$msg'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Позже', style: TextStyle(color: EsepColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

// ── Toggle tab ──────────────────────────────────────────────────────────────

class _ToggleTab extends StatelessWidget {
  const _ToggleTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? EsepColors.cardLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)]
                : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? EsepColors.textPrimary : EsepColors.textSecondary,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: EsepColors.income,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ── Plan card ───────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.tier,
    required this.yearly,
    required this.highlighted,
    this.badge,
    this.onTap,
  });
  final SubscriptionTier tier;
  final bool yearly;
  final bool highlighted;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final price = yearly ? tier.yearlyPrice : tier.monthlyPrice;
    final period = yearly ? '/год' : '/мес';

    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: highlighted ? EsepColors.primary.withValues(alpha: 0.06) : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? EsepColors.primary : EsepColors.divider,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(tier.label, style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: highlighted ? EsepColors.primary : EsepColors.textPrimary,
              )),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: highlighted ? EsepColors.primary : EsepColors.textSecondary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(badge!, style: const TextStyle(
                    fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700,
                  )),
                ),
              ],
            ]),
            const SizedBox(height: 2),
            Text(tier.shortFeatures, style: const TextStyle(
              fontSize: 12, color: EsepColors.textSecondary,
            )),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            _formatPrice(price),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: EsepColors.textPrimary),
          ),
          Text(period, style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
          if (yearly) ...[
            Text(
              '${_formatPrice(tier.monthlyPrice)}/мес',
              style: const TextStyle(
                fontSize: 11,
                color: EsepColors.textDisabled,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ],
        ]),
      ]),
    ),
    );
  }

  static String _formatPrice(int price) {
    if (price >= 1000) {
      final thousands = price ~/ 1000;
      final remainder = price % 1000;
      if (remainder == 0) return '$thousands 000 ₸';
      return '$thousands ${remainder.toString().padLeft(3, '0')} ₸';
    }
    return '$price ₸';
  }
}
