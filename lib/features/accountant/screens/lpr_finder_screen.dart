import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/api_client.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// LPR Finder Screen — поиск и CRM потенциальных клиентов для бухгалтера
// ═══════════════════════════════════════════════════════════════════════════════

class LprFinderScreen extends StatefulWidget {
  const LprFinderScreen({super.key});

  @override
  State<LprFinderScreen> createState() => _LprFinderScreenState();
}

class _LprFinderScreenState extends State<LprFinderScreen> {
  final _searchController = TextEditingController();
  String _selectedCity = '';
  bool _searching = false;
  bool _loadingSaved = false;
  String? _searchError;

  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _savedContacts = [];

  static const _cities = [
    {'label': 'Все города', 'value': ''},
    {'label': 'Алматы', 'value': 'алматы'},
    {'label': 'Астана', 'value': 'астана'},
    {'label': 'Шымкент', 'value': 'шымкент'},
    {'label': 'Караганда', 'value': 'караганда'},
    {'label': 'Другой', 'value': 'другой'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── API calls ──────────────────────────────────────────────────────────────

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.length < 2) {
      setState(() => _searchError = 'Введите минимум 2 символа');
      return;
    }

    setState(() {
      _searching = true;
      _searchError = null;
      _searchResults = [];
    });

    try {
      final cityParam = _selectedCity.isNotEmpty ? '&city=$_selectedCity' : '';
      final data = await ApiClient.get(
        '/lpr/search?q=${Uri.encodeComponent(q)}$cityParam',
      );
      final results = (data['results'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _searchError = e.message;
        _searching = false;
      });
    } catch (e) {
      setState(() {
        _searchError = 'Нет соединения с сервером';
        _searching = false;
      });
    }
  }

  Future<void> _loadSavedContacts() async {
    setState(() => _loadingSaved = true);
    try {
      final data = await ApiClient.get('/lpr/saved');
      final contacts = (data['contacts'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      setState(() {
        _savedContacts = contacts;
        _loadingSaved = false;
      });
    } catch (_) {
      setState(() => _loadingSaved = false);
    }
  }

  Future<void> _saveContact(Map<String, dynamic> contact) async {
    try {
      final data = await ApiClient.post('/lpr/save', {
        'bin': contact['bin'],
        'companyName': contact['companyName'] ?? contact['company_name'] ?? '',
        'directorName':
            contact['directorName'] ?? contact['director_name'] ?? '',
        'phone': contact['phone'] ?? '',
        'email': contact['email'] ?? '',
        'source': contact['source'] ?? 'stat.gov.kz',
        'city': contact['city'] ?? _selectedCity,
        'activity': contact['activity'] ?? '',
        'notes': contact['notes'] ?? '',
      });
      final saved = Map<String, dynamic>.from(data as Map);
      setState(() {
        _savedContacts.insert(0, saved);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Контакт сохранён')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка сохранения')),
        );
      }
    }
  }

  Future<void> _deleteContact(String id) async {
    try {
      await ApiClient.delete('/lpr/$id');
      setState(() {
        _savedContacts.removeWhere((c) => c['id'] == id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Контакт удалён')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка удаления')),
        );
      }
    }
  }

  Future<void> _showAddContactDialog() async {
    final binCtl = TextEditingController();
    final nameCtl = TextEditingController();
    final directorCtl = TextEditingController();
    final phoneCtl = TextEditingController();
    final emailCtl = TextEditingController();
    final notesCtl = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить контакт'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: binCtl,
                decoration: const InputDecoration(labelText: 'БИН'),
                keyboardType: TextInputType.number,
                maxLength: 12,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtl,
                decoration:
                    const InputDecoration(labelText: 'Название компании *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: directorCtl,
                decoration: const InputDecoration(labelText: 'Руководитель'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtl,
                decoration: const InputDecoration(labelText: 'Телефон'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emailCtl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtl,
                decoration: const InputDecoration(labelText: 'Заметки'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('Укажите название компании')),
                );
                return;
              }
              Navigator.pop(ctx, {
                'bin': binCtl.text.trim(),
                'companyName': nameCtl.text.trim(),
                'directorName': directorCtl.text.trim(),
                'phone': phoneCtl.text.trim(),
                'email': emailCtl.text.trim(),
                'notes': notesCtl.text.trim(),
              });
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _saveContact({...result, 'source': 'manual'});
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Поиск клиентов (ЛПР)'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.add_circle),
            tooltip: 'Добавить контакт вручную',
            onPressed: _showAddContactDialog,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Search area ──────────────────────────────────────────────
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Компания / вид деятельности',
                hintText: 'бухгалтерские услуги',
                prefixIcon: const Icon(Iconsax.search_normal),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Iconsax.close_circle, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                            _searchError = null;
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),

            // ── City dropdown ────────────────────────────────────────────
            DropdownButtonFormField<String>(
              initialValue: _selectedCity,
              decoration: const InputDecoration(
                labelText: 'Город',
                prefixIcon: Icon(Iconsax.location),
              ),
              items: _cities
                  .map((c) => DropdownMenuItem(
                        value: c['value'],
                        child: Text(c['label']!),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCity = v ?? ''),
            ),
            const SizedBox(height: 12),

            // ── Action buttons ───────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _searching ? null : _search,
                    icon: const Icon(Iconsax.search_normal_1),
                    label: const Text('Найти'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/bin-lookup'),
                    icon: const Icon(Iconsax.document),
                    label: const Text('Поиск по БИН'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      side: const BorderSide(color: EsepColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Search results ───────────────────────────────────────────
            if (_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: EsepColors.primary),
                      SizedBox(height: 12),
                      Text('Поиск...',
                          style: TextStyle(
                              color: EsepColors.textSecondary, fontSize: 14)),
                    ],
                  ),
                ),
              ),

            if (_searchError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    _searchError!,
                    style: const TextStyle(
                        color: EsepColors.expense, fontSize: 14),
                  ),
                ),
              ),

            if (_searchResults.isNotEmpty) ...[
              _SectionHeader(
                title: 'Результаты поиска (${_searchResults.length})',
                icon: Iconsax.search_status,
              ),
              const SizedBox(height: 8),
              ..._searchResults.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SearchResultCard(
                      data: r,
                      onSave: () => _saveContact(r),
                    ),
                  )),
              const SizedBox(height: 16),
            ],

            // ── Saved contacts ───────────────────────────────────────────
            _SectionHeader(
              title: 'Сохранённые контакты (${_savedContacts.length})',
              icon: Iconsax.book_saved,
            ),
            const SizedBox(height: 8),

            if (_loadingSaved)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child:
                      CircularProgressIndicator(color: EsepColors.primary),
                ),
              )
            else if (_savedContacts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Iconsax.people,
                          size: 48,
                          color: EsepColors.textSecondary
                              .withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      const Text(
                        'Нет сохранённых контактов.\nИщите компании или добавьте вручную.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: EsepColors.textSecondary, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._savedContacts.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Dismissible(
                      key: Key(c['id']?.toString() ?? c['bin'] ?? ''),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: EsepColors.expense.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Iconsax.trash,
                            color: EsepColors.expense),
                      ),
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Удалить контакт?'),
                            content: Text(c['companyName'] ?? ''),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Отмена'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Удалить',
                                    style:
                                        TextStyle(color: EsepColors.expense)),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (_) {
                        final id = c['id']?.toString();
                        if (id != null) _deleteContact(id);
                      },
                      child: _SavedContactCard(data: c),
                    ),
                  )),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Section header
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: EsepColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: EsepColors.textPrimary,
            ),
          ),
        ],
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Search result card (from stat.gov.kz)
// ═══════════════════════════════════════════════════════════════════════════════

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.data, required this.onSave});
  final Map<String, dynamic> data;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final name = data['companyName']?.toString() ?? '-';
    final bin = data['bin']?.toString() ?? '';
    final director = data['directorName']?.toString() ?? '';
    final address = data['address']?.toString() ?? '';
    final activity = data['activity']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EsepColors.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EsepColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Company name ─────────────────────────────────────────────
          Row(
            children: [
              const Icon(Iconsax.building_4,
                  size: 16, color: EsepColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: EsepColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),

          if (bin.isNotEmpty) ...[
            const SizedBox(height: 6),
            _DetailRow(
                icon: Iconsax.document, label: 'БИН', value: bin),
          ],
          if (director.isNotEmpty) ...[
            const SizedBox(height: 4),
            _DetailRow(
                icon: Iconsax.user, label: 'Руководитель', value: director),
          ],
          if (address.isNotEmpty) ...[
            const SizedBox(height: 4),
            _DetailRow(
                icon: Iconsax.location, label: 'Адрес', value: address),
          ],
          if (activity.isNotEmpty) ...[
            const SizedBox(height: 4),
            _DetailRow(
                icon: Iconsax.briefcase,
                label: 'Деятельность',
                value: activity),
          ],

          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSave,
              icon: const Icon(Iconsax.save_add, size: 18),
              label: const Text('Сохранить в контакты'),
              style: OutlinedButton.styleFrom(
                foregroundColor: EsepColors.primary,
                side: const BorderSide(color: EsepColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Saved contact card
// ═══════════════════════════════════════════════════════════════════════════════

class _SavedContactCard extends StatelessWidget {
  const _SavedContactCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final name = data['companyName']?.toString() ?? '-';
    final bin = data['bin']?.toString() ?? '';
    final director = data['directorName']?.toString() ?? '';
    final phone = data['phone']?.toString() ?? '';
    final email = data['email']?.toString() ?? '';
    final city = data['city']?.toString() ?? '';
    final activity = data['activity']?.toString() ?? '';
    final notes = data['notes']?.toString() ?? '';
    final source = data['source']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EsepColors.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EsepColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: EsepColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Iconsax.building_4,
                    color: EsepColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: EsepColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (bin.isNotEmpty)
                      Text(
                        'БИН: $bin',
                        style: const TextStyle(
                            fontSize: 12, color: EsepColors.textSecondary),
                      ),
                  ],
                ),
              ),
              if (source.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: EsepColors.textSecondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    source,
                    style: const TextStyle(
                        fontSize: 10, color: EsepColors.textSecondary),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Details ──────────────────────────────────────────────────
          if (director.isNotEmpty)
            _DetailRow(
                icon: Iconsax.user, label: 'Руководитель', value: director),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 4),
            _DetailRow(
                icon: Iconsax.call, label: 'Телефон', value: phone),
          ],
          if (email.isNotEmpty) ...[
            const SizedBox(height: 4),
            _DetailRow(
                icon: Iconsax.sms, label: 'Email', value: email),
          ],
          if (city.isNotEmpty) ...[
            const SizedBox(height: 4),
            _DetailRow(
                icon: Iconsax.location, label: 'Город', value: city),
          ],
          if (activity.isNotEmpty) ...[
            const SizedBox(height: 4),
            _DetailRow(
                icon: Iconsax.briefcase,
                label: 'Деятельность',
                value: activity),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: EsepColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Iconsax.note_1,
                      size: 14, color: EsepColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      notes,
                      style: const TextStyle(
                          fontSize: 12, color: EsepColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shared detail row
// ═══════════════════════════════════════════════════════════════════════════════

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 13, color: EsepColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(
                fontSize: 12, color: EsepColors.textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: EsepColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}
