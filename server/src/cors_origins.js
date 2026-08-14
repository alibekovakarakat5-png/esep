// Origin'ы, которым разрешён доступ к API. Единый источник правды —
// используется в index.js и покрыт test/cors_origins.test.js.
const ALLOWED_ORIGINS = [
  // Production — основные домены
  'https://esepkz.com',
  'https://www.esepkz.com',
  'https://app.esepkz.com',
  'https://api.esepkz.com',
  // Лендинги сегментов — с них приходят заявки на /api/lead
  'https://buhfirma.esepkz.com',   // бухгалтерские фирмы
  'https://business.esepkz.com',   // курьерские службы, таксопарки, маркетплейсы
  'https://automation.esepkz.com', // Esep Automation (интеграции)
  'https://esep-auto.vercel.app',
  // Старые URL (на переходный период — потом удалим)
  'https://esepkz.vercel.app',
  'https://alibekovakarakat5-png.github.io',
  'https://esep-production.up.railway.app',
  // Local dev
  'http://localhost:5500',
  'http://localhost:8080',
  'http://localhost:3000',
  'http://localhost:3334',
  'http://localhost:3336',
  'http://localhost:5173',
];

/// Origin — это всегда scheme://host:port без пути, поэтому сравниваем точно.
/// Прежняя проверка `origin.startsWith(allowed)` пропускала подделки вида
/// `https://esepkz.com.evil.example`.
/// Пустой origin (curl, сервер-сервер, same-origin) разрешаем.
function isAllowedOrigin(origin) {
  if (!origin) return true;
  return ALLOWED_ORIGINS.includes(origin);
}

module.exports = { ALLOWED_ORIGINS, isAllowedOrigin };
