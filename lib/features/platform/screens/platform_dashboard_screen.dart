/// Главный экран для enterprise-клиентов (Platform API).
///
/// Показывает после логина если user.tier == 'enterprise'.
/// Заменяет обычный дашборд Esep (учёт/счета/налоги).
///
/// Дизайн: тёмно-синий брендинг как на business.esepkz.com.
/// Desktop-first с constrained-шириной 1180px.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/platform_api_service.dart';
import '../widgets/service_card.dart';
import 'service_test_screen.dart' show ServiceTestScreen;

// ─── Esep Business brand palette ────────────────────────────────────────────
// Совпадает со стилями business.esepkz.com (см. сайт/client-demo/style.css).
class _Brand {
  static const Color bgDark       = Color(0xFF0B1426);
  static const Color cardDark     = Color(0xFF14213D);
  static const Color cardDarkAlt  = Color(0xFF1E2D4F);
  static const Color borderDark   = Color(0xFF1F2D4D);
  static const Color accent       = Color(0xFF1E5BFF);
  static const Color accentBright = Color(0xFF6A8DFF);
  static const Color textOnDark   = Colors.white;
  static const Color textDim      = Color(0xFF98A4C0);
  static const Color bgLight      = Color(0xFFFAFBFD);
  static const Color cardLight    = Colors.white;
  static const Color border       = Color(0xFFE4E9F2);
  static const Color text         = Color(0xFF0B1426);
  static const Color textSecondary= Color(0xFF5A6986);
  static const Color green        = Color(0xFF00B870);
  static const Color orange       = Color(0xFFF59E0B);
  static const Color red          = Color(0xFFEF4444);

  static const double maxWidth    = 1180.0;
}

class PlatformDashboardScreen extends ConsumerStatefulWidget {
  const PlatformDashboardScreen({super.key});

  @override
  ConsumerState<PlatformDashboardScreen> createState() =>
      _PlatformDashboardScreenState();
}

class _PlatformDashboardScreenState
    extends ConsumerState<PlatformDashboardScreen> {
  PlatformAccount? _account;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final acc = await PlatformApiService.myAccount();
      setState(() {
        _account = acc;
        _loading = false;
        if (acc == null) {
          _error = 'У вашего аккаунта нет доступа к Platform API.';
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Ошибка загрузки данных: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Brand.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: _buildTopBar(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _Brand.accent))
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: _Brand.bgDark,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _Brand.maxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              child: Row(
                children: [
                  // Logo mark
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_Brand.accent, _Brand.accentBright],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'E',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 17,
                        color: _Brand.textOnDark,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                      children: [
                        TextSpan(text: 'esep'),
                        TextSpan(
                          text: 'platform',
                          style: TextStyle(
                            color: _Brand.textDim,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 28),
                  const Text(
                    'Корпоративный кабинет',
                    style: TextStyle(
                      color: _Brand.textDim,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Iconsax.refresh, color: _Brand.textOnDark, size: 20),
                    onPressed: _load,
                    tooltip: 'Обновить',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _Brand.orange.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Iconsax.info_circle,
                  size: 36,
                  color: _Brand.orange,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15.5,
                  color: _Brand.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Brand.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: _load,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final acc = _account!;
    return RefreshIndicator(
      color: _Brand.accent,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _Brand.maxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildClientHero(acc),
                  const SizedBox(height: 24),
                  _buildStatsRow(acc),
                  const SizedBox(height: 40),
                  _sectionTitle('Подключённые сервисы'),
                  const SizedBox(height: 6),
                  _sectionSub(
                    'Кликните по карточке, чтобы попробовать сервис вживую с реальным API',
                  ),
                  const SizedBox(height: 18),
                  _buildServicesGrid(acc),
                  const SizedBox(height: 40),
                  _buildIntegrationCard(acc),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: _Brand.text,
        letterSpacing: -0.4,
      ),
    );
  }

  Widget _sectionSub(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14.5,
        color: _Brand.textSecondary,
        height: 1.45,
      ),
    );
  }

  Widget _buildClientHero(PlatformAccount acc) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_Brand.bgDark, _Brand.cardDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _Brand.bgDark.withValues(alpha: 0.20),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _Brand.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Iconsax.building_4,
              color: _Brand.accentBright,
              size: 28,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  acc.clientName,
                  style: const TextStyle(
                    color: _Brand.textOnDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      acc.clientBin != null ? 'БИН: ${acc.clientBin}' : 'Enterprise клиент',
                      style: const TextStyle(
                        color: _Brand.textDim,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _Brand.green.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'ENTERPRISE',
                        style: TextStyle(
                          color: Color(0xFF6CE2A8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // API key chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _Brand.cardDarkAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _Brand.borderDark),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Iconsax.key, color: _Brand.textDim, size: 14),
                const SizedBox(width: 8),
                Text(
                  _maskKey(acc.apiKey),
                  style: const TextStyle(
                    color: _Brand.textOnDark,
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _maskKey(String key) {
    if (key.length < 12) return key;
    return '${key.substring(0, 8)}…${key.substring(key.length - 4)}';
  }

  Widget _buildStatsRow(PlatformAccount acc) {
    final usagePercent = acc.monthlyQuota > 0
        ? (acc.requestsThisMonth / acc.monthlyQuota * 100).toStringAsFixed(1)
        : '∞';

    return LayoutBuilder(builder: (ctx, c) {
      final isNarrow = c.maxWidth < 720;
      final children = [
        _statCard(
          'Запросов в месяц',
          '${acc.requestsThisMonth}',
          '/${acc.monthlyQuota > 0 ? acc.monthlyQuota : '∞'} ($usagePercent%)',
          Iconsax.activity,
          _Brand.accent,
        ),
        _statCard(
          'Фискализировано',
          '${acc.receipts.issued}',
          'из ${acc.receipts.total} чеков',
          Iconsax.tick_circle,
          _Brand.green,
        ),
        _statCard(
          'Сумма выплат',
          _formatMoney(acc.receipts.totalAmount),
          '₸ всего',
          Iconsax.money,
          _Brand.orange,
        ),
      ];
      if (isNarrow) {
        return Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      }
      return Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            Expanded(child: children[i]),
            if (i < children.length - 1) const SizedBox(width: 16),
          ],
        ],
      );
    });
  }

  Widget _statCard(String label, String value, String sub, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Brand.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Brand.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E1A34).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _Brand.text,
              letterSpacing: -0.6,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: _Brand.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 12,
              color: _Brand.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesGrid(PlatformAccount acc) {
    final services = _buildServices(acc);
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      final cols = w >= 1000 ? 3 : w >= 640 ? 2 : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          mainAxisExtent: 180,
        ),
        itemCount: services.length,
        itemBuilder: (_, i) {
          final s = services[i];
          return ServiceCard(
            number: s.number,
            title: s.title,
            subtitle: s.subtitle,
            icon: s.icon,
            status: s.status,
            enabled: s.enabled,
            onTap: s.enabled
                ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ServiceTestScreen(
                        serviceCode: s.code,
                        title: s.title,
                        apiKey: acc.apiKey,
                      ),
                    ))
                : null,
          );
        },
      );
    });
  }

  Widget _buildIntegrationCard(PlatformAccount acc) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _Brand.bgDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _Brand.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Iconsax.code, color: _Brand.accentBright, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Интеграция в вашу систему',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: _Brand.textOnDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _kv('API URL', acc.apiBaseUrl),
          _kv('Заголовок', 'X-Platform-Key: <ваш ключ>'),
          _kv('Главный endpoint', 'POST /process-payment'),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _Brand.cardDark,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _Brand.borderDark),
            ),
            child: const Text(
              'Вызывайте /process-payment на каждую выплату курьеру. Внутри выполняется: '
              'валидация ИИН → проверка СНР → контроль лимита 300 МРП → фискализация через Webkassa → '
              'регистрация чека в КГД. Один HTTP-запрос вместо девяти.',
              style: TextStyle(
                fontSize: 13,
                color: _Brand.textDim,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              k,
              style: const TextStyle(
                fontSize: 12.5,
                color: _Brand.textDim,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: _Brand.textOnDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMoney(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  List<_ServiceDef> _buildServices(PlatformAccount acc) {
    return [
      _ServiceDef(
        number: 1,
        code: 'process_payment',
        title: 'Magic — выплата курьеру',
        subtitle: 'Один вызов: проверка + фискализация',
        icon: Iconsax.flash_15,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('process_payment'),
      ),
      _ServiceDef(
        number: 2,
        code: 'taxpayer_info',
        title: 'СНР и ОКЭД',
        subtitle: 'Проверка по БИН/ИИН через stat.gov.kz',
        icon: Iconsax.search_normal,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('taxpayer_info'),
      ),
      _ServiceDef(
        number: 3,
        code: 'taxpayer_info',
        title: 'Статус ИП / ФЛ / ТОО',
        subtitle: 'Тип юр.формы из реестра',
        icon: Iconsax.profile_2user,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('taxpayer_info'),
      ),
      _ServiceDef(
        number: 4,
        code: 'iin_validate',
        title: 'Валидация ИИН',
        subtitle: 'Алгоритмическая проверка контрольной цифры',
        icon: Iconsax.shield_tick,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('iin_validate'),
      ),
      _ServiceDef(
        number: 5,
        code: 'cancel_order',
        title: 'Аннулирование чека',
        subtitle: 'Soft cancel заказа до фискализации',
        icon: Iconsax.close_circle,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('cancel_receipt'),
      ),
      _ServiceDef(
        number: 6,
        code: 'receipt_status',
        title: 'Статус чека',
        subtitle: 'Фискальный № + QR от КГД',
        icon: Iconsax.receipt,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('receipt_status'),
      ),
      _ServiceDef(
        number: 7,
        code: 'income_limit',
        title: 'Лимит 300 МРП',
        subtitle: 'Учёт месячного дохода самозанятого',
        icon: Iconsax.chart_2,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('income_limit'),
      ),
      _ServiceDef(
        number: 8,
        code: 'self_employed_registry',
        title: 'Реестр самозанятых',
        subtitle: 'Источник: КГД ИСНА (договор оформляется)',
        icon: Iconsax.people,
        status: ServiceStatus.demo,
        enabled: acc.hasFeature('self_employed_registry'),
      ),
      _ServiceDef(
        number: 9,
        code: 'benefits',
        title: 'Льготы самозанятых',
        subtitle: 'Молодёжь / многодетные / инвалиды',
        icon: Iconsax.heart,
        status: ServiceStatus.demo,
        enabled: acc.hasFeature('benefits'),
      ),
    ];
  }
}

class _ServiceDef {
  final int number;
  final String code;
  final String title;
  final String subtitle;
  final IconData icon;
  final ServiceStatus status;
  final bool enabled;

  _ServiceDef({
    required this.number,
    required this.code,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
    required this.enabled,
  });
}
