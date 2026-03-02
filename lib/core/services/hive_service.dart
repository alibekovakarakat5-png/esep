import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction.dart';
import '../models/client.dart';
import '../models/invoice.dart';

class HiveService {
  static const String transactionsBox = 'transactions';
  static const String clientsBox = 'clients';
  static const String invoicesBox = 'invoices';
  static const String settingsBox = 'settings';

  static Future<void> init() async {
    await Hive.initFlutter();

    Hive.registerAdapter(TransactionAdapter());
    Hive.registerAdapter(ClientAdapter());
    Hive.registerAdapter(InvoiceAdapter());
    Hive.registerAdapter(InvoiceItemAdapter());
    Hive.registerAdapter(InvoiceStatusAdapter());

    await Hive.openBox<Transaction>(transactionsBox);
    await Hive.openBox<Client>(clientsBox);
    await Hive.openBox<Invoice>(invoicesBox);
    await Hive.openBox(settingsBox);
  }

  static Box<Transaction> get transactions => Hive.box<Transaction>(transactionsBox);
  static Box<Client> get clients => Hive.box<Client>(clientsBox);
  static Box<Invoice> get invoices => Hive.box<Invoice>(invoicesBox);
  static Box get settings => Hive.box(settingsBox);
}
