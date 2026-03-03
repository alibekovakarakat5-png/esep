import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/hive_service.dart';

class CompanyInfo {
  final String name;
  final String iin;
  final String? address;
  final String? phone;
  final String? email;
  final String? bankName;
  final String? iik;   // ИИК (IBAN)
  final String? bik;   // БИК банка
  final String? kbe;   // КБе (код бенефициара)

  const CompanyInfo({
    required this.name,
    required this.iin,
    this.address,
    this.phone,
    this.email,
    this.bankName,
    this.iik,
    this.bik,
    this.kbe,
  });

  bool get isComplete => name.isNotEmpty && iin.isNotEmpty;

  static const empty = CompanyInfo(name: '', iin: '');
}

class CompanyNotifier extends StateNotifier<CompanyInfo> {
  CompanyNotifier() : super(CompanyInfo.empty) {
    _load();
  }

  void _load() {
    final box = HiveService.settings;
    state = CompanyInfo(
      name:     box.get('company_name',  defaultValue: '') as String,
      iin:      box.get('company_iin',   defaultValue: '') as String,
      address:  box.get('company_addr')  as String?,
      phone:    box.get('company_phone') as String?,
      email:    box.get('company_email') as String?,
      bankName: box.get('company_bank')  as String?,
      iik:      box.get('company_iik')   as String?,
      bik:      box.get('company_bik')   as String?,
      kbe:      box.get('company_kbe')   as String?,
    );
  }

  Future<void> save({
    required String name,
    required String iin,
    String? address,
    String? phone,
    String? email,
    String? bankName,
    String? iik,
    String? bik,
    String? kbe,
  }) async {
    final box = HiveService.settings;
    await box.put('company_name',  name);
    await box.put('company_iin',   iin);
    await box.put('company_addr',  address ?? '');
    await box.put('company_phone', phone ?? '');
    await box.put('company_email', email ?? '');
    await box.put('company_bank',  bankName ?? '');
    await box.put('company_iik',   iik ?? '');
    await box.put('company_bik',   bik ?? '');
    await box.put('company_kbe',   kbe ?? '');
    _load();
  }
}

final companyProvider =
    StateNotifierProvider<CompanyNotifier, CompanyInfo>((ref) {
  return CompanyNotifier();
});
