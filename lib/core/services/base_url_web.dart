import 'package:web/web.dart' as web;

String detectApiBase() {
  final hostname = web.window.location.hostname;
  // Dev: Flutter runs at localhost:PORT, backend at localhost:3001
  if (hostname == 'localhost' || hostname == '127.0.0.1') {
    return 'http://localhost:3001/api';
  }
  // Prod: Railway backend
  return 'https://esep-production.up.railway.app/api';
}
