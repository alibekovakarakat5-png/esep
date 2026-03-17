import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/subscription_provider.dart';

class BinLookupScreen extends ConsumerStatefulWidget {
  const BinLookupScreen({super.key});

  @override
  ConsumerState<BinLookupScreen> createState() => _BinLookupScreenState();
}

enum _ScreenState { initial, loading, success, error }

class _BinLookupScreenState extends ConsumerState<BinLookupScreen> {
  final _binController = TextEditingController();
  _ScreenState _state = _ScreenState.initial;
  Map<String, dynamic>? _result;
  String _errorMessage = '';

  @override
  void dispose() {
    _binController.dispose();
    super.dispose();
  }

  int _todayBinLookups() {
    final box = Hive.box('settings');
    final dateKey = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = box.get('bin_lookup_date', defaultValue: '') as String;
    if (savedDate != dateKey) return 0;
    return box.get('bin_lookup_count', defaultValue: 0) as int;
  }

  void _incrementBinLookup() {
    final box = Hive.box('settings');
    final dateKey = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = box.get('bin_lookup_date', defaultValue: '') as String;
    if (savedDate != dateKey) {
      box.put('bin_lookup_date', dateKey);
      box.put('bin_lookup_count', 1);
    } else {
      final count = box.get('bin_lookup_count', defaultValue: 0) as int;
      box.put('bin_lookup_count', count + 1);
    }
  }

  Future<void> _search() async {
    final sub = ref.read(subscriptionProvider);
    if (!canUseBinLookup(sub, _todayBinLookups())) {
      showPaywall(context, feature: 'Поиск по БИН');
      return;
    }

    final bin = _binController.text.trim();
    if (bin.length != 12) {
      setState(() {
        _state = _ScreenState.error;
        _errorMessage = 'БИН должен содержать 12 цифр';
      });
      return;
    }

    setState(() => _state = _ScreenState.loading);

    try {
      final response = await http.get(
        Uri.parse('https://esep-production.up.railway.app/api/bin/$bin'),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 || response.statusCode == 502) {
        // 502 = stat.gov.kz unavailable, but we still get BIN-derived info
        _incrementBinLookup();
        setState(() {
          _result = data;
          _state = _ScreenState.success;
        });
      } else if (response.statusCode == 404) {
        setState(() {
          _state = _ScreenState.error;
          _errorMessage = 'Организация с БИН $bin не найдена';
        });
      } else {
        setState(() {
          _state = _ScreenState.error;
          _errorMessage = data['error']?.toString() ?? 'Ошибка сервера (${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _state = _ScreenState.error;
        _errorMessage = 'Нет соединения с сервером';
      });
    }
  }

  void _copyBin() {
    final bin = _result?['bin']?.toString() ?? _binController.text.trim();
    if (bin.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: bin));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('БИН скопирован'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Поиск по БИН')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- Search field ---
            TextField(
              controller: _binController,
              keyboardType: TextInputType.number,
              maxLength: 12,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Введите БИН',
                hintText: '123456789012',
                prefixIcon: const Icon(Iconsax.search_normal),
                suffixIcon: _binController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Iconsax.close_circle, size: 20),
                        onPressed: () {
                          _binController.clear();
                          setState(() => _state = _ScreenState.initial);
                        },
                      )
                    : null,
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),

            // --- Search button ---
            ElevatedButton.icon(
              onPressed: _state == _ScreenState.loading ? null : _search,
              icon: const Icon(Iconsax.search_normal_1),
              label: const Text('Найти'),
            ),
            const SizedBox(height: 24),

            // --- Content area ---
            if (_state == _ScreenState.initial) _buildInitialHint(),
            if (_state == _ScreenState.loading) _buildLoading(),
            if (_state == _ScreenState.error) _buildError(),
            if (_state == _ScreenState.success && _result != null)
              _buildResult(_result!),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Column(
          children: [
            Icon(Iconsax.building_4, size: 56, color: EsepColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'Введите 12-значный БИН\nдля поиска информации',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: EsepColors.textSecondary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.only(top: 48),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(color: EsepColors.primary),
            SizedBox(height: 16),
            Text(
              'Поиск...',
              style: TextStyle(color: EsepColors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Center(
        child: Column(
          children: [
            const Icon(Iconsax.warning_2, size: 56, color: EsepColors.expense),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: EsepColors.expense,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(Map<String, dynamic> data) {
    final name = data['name']?.toString() ?? '-';
    final bin = data['bin']?.toString() ?? '-';
    final director = data['director']?.toString() ?? '-';
    final address = data['address']?.toString() ?? '-';
    final activityCode = data['activityCode']?.toString() ?? '';
    final activityName = data['activityName']?.toString() ?? '-';
    final registrationDate = data['registrationDate']?.toString() ?? '-';
    final entityType = data['entityType']?.toString() ?? '-';
    final isIP = data['isIP'] == true;

    final activity = activityCode.isNotEmpty
        ? '$activityCode — $activityName'
        : activityName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Header: icon + name ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: isIP
                      ? EsepColors.income.withValues(alpha: 0.12)
                      : EsepColors.info.withValues(alpha: 0.12),
                  child: Icon(
                    isIP ? Iconsax.user : Iconsax.building_4,
                    color: isIP ? EsepColors.income : EsepColors.info,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: EsepColors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isIP
                              ? EsepColors.income.withValues(alpha: 0.12)
                              : EsepColors.info.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          entityType,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isIP ? EsepColors.income : EsepColors.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(color: EsepColors.divider, height: 1),
            const SizedBox(height: 12),

            // --- Info rows ---
            _InfoRow(
              icon: Iconsax.document,
              label: 'БИН',
              value: bin,
              trailing: IconButton(
                icon: const Icon(Iconsax.copy, size: 18),
                color: EsepColors.primary,
                tooltip: 'Скопировать БИН',
                onPressed: _copyBin,
              ),
            ),
            _InfoRow(
              icon: Iconsax.user,
              label: 'Руководитель',
              value: director,
            ),
            _InfoRow(
              icon: Iconsax.location,
              label: 'Адрес',
              value: address,
            ),
            _InfoRow(
              icon: Iconsax.briefcase,
              label: 'Вид деятельности',
              value: activity,
            ),
            _InfoRow(
              icon: Iconsax.calendar,
              label: 'Дата регистрации',
              value: registrationDate,
              showDivider: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: EsepColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: EsepColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: EsepColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        if (showDivider)
          const Divider(color: EsepColors.divider, height: 1),
      ],
    );
  }
}
