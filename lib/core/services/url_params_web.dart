import 'package:web/web.dart' as web;

/// Web: читает query-параметры из window.location.search.
Map<String, String> readUrlParams() {
  final search = web.window.location.search;
  if (search.isEmpty || search == '?') return const {};
  final uri = Uri.parse('http://x${search}');
  return uri.queryParameters;
}

/// Web: убирает указанные ключи из URL без перезагрузки.
/// Используется чтобы скрыть токен impersonation после прочтения.
void clearUrlParams(List<String> keys) {
  final loc = web.window.location;
  final uri = Uri.parse(loc.href);
  final params = Map<String, String>.from(uri.queryParameters);
  for (final k in keys) {
    params.remove(k);
  }
  final newQuery = params.isEmpty
      ? ''
      : '?${params.entries.map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}'
        ).join('&')}';
  final cleanUrl = '${loc.pathname}$newQuery${loc.hash}';
  web.window.history.replaceState(null, '', cleanUrl);
}
