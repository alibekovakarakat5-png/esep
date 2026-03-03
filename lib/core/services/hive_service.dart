import 'package:hive_flutter/hive_flutter.dart';
import '../models/client.dart';

class HiveService {
  static const String clientsBox = 'clients';
  static const String settingsBox = 'settings';

  static Future<void> init() async {
    await Hive.initFlutter();

    Hive.registerAdapter(ClientAdapter());

    await Hive.openBox<Client>(clientsBox);
    await Hive.openBox(settingsBox);
  }

  static Box<Client> get clients => Hive.box<Client>(clientsBox);
  static Box get settings => Hive.box(settingsBox);
}
