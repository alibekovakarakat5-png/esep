/// Главный экран для enterprise-клиентов (Platform API).
///
/// Показывает после логина если user.tier == 'enterprise'.
/// Заменяет обычный дашборд Esep (учёт/счета/налоги).
///
/// Содержит:
///   - Шапка: имя клиента, его БИН, тариф
///   - Stats cards: запросов в месяц, фискализаций, выплат
///   - Grid 9 сервисов как кликабельные карточки
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/platform_api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/service_card.dart';
import 'service_test_screen.dart' show ServiceTestScreen;

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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Platform API — Корпоративный кабинет'),
        backgroundColor: EsepColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Iconsax.refresh),
            onPressed: _load,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Iconsax.info_circle, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final acc = _account!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildClientHeader(acc),
          const SizedBox(height: 16),
          _buildStatsRow(acc),
          const SizedBox(height: 24),
          const Text(
            'Подключённые сервисы',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Кликните по карточке, чтобы попробовать сервис вживую',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 12),
          _buildServicesGrid(acc),
          const SizedBox(height: 24),
          _buildIntegrationCard(acc),
        ],
      ),
    );
  }

  Widget _buildClientHeader(PlatformAccount acc) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F2B46), Color(0xFF1E3A5F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.building_4, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      acc.clientName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      acc.clientBin != null ? 'БИН: ${acc.clientBin}' : 'Enterprise клиент',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'ENTERPRISE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(PlatformAccount acc) {
    final usagePercent = acc.monthlyQuota > 0
        ? (acc.requestsThisMonth / acc.monthlyQuota * 100).toStringAsFixed(1)
        : '∞';

    return Row(
      children: [
        Expanded(
          child: _miniStat(
            'Запросов в месяц',
            '${acc.requestsThisMonth}',
            '/${acc.monthlyQuota > 0 ? acc.monthlyQuota : '∞'} ($usagePercent%)',
            Iconsax.activity,
            const Color(0xFF0EA5E9),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniStat(
            'Фискализировано',
            '${acc.receipts.issued}',
            'из ${acc.receipts.total} чеков',
            Iconsax.tick_circle,
            const Color(0xFF22C55E),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniStat(
            'Сумма выплат',
            _formatMoney(acc.receipts.totalAmount),
            '₸ всего',
            Iconsax.money,
            const Color(0xFFF59E0B),
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value, String sub, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
          Text(sub, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildServicesGrid(PlatformAccount acc) {
    final services = _buildServices(acc);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
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
  }

  Widget _buildIntegrationCard(PlatformAccount acc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.code, color: Color(0xFF0EA5E9)),
              const SizedBox(width: 8),
              const Text(
                'Интеграция в вашу систему',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _kv('API URL:', acc.apiBaseUrl),
          _kv('Заголовок:', 'X-Platform-Key: <ваш ключ>'),
          _kv('Получить ключ:', 'через раздел "Настройки → API"'),
          const SizedBox(height: 8),
          Text(
            'Главный endpoint: POST /process-payment — вызывайте на каждую выплату курьеру. '
            'Внутри выполняется валидация ИИН, проверка СНР, контроль лимита 300 МРП '
            'и фискализация через Webkassa.',
            style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
          Expanded(
            child: SelectableText(
              v,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Colors.grey[800],
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
