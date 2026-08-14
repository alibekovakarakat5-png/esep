// Тонкий клиент Connect (наш WhatsApp Business API).
//
// Нужен серверу Esep, чтобы бот сбора документов писал клиентам бухгалтера.
// Настраивается тремя переменными; если их нет — sendText честно говорит
// «не настроено», а не притворяется, что отправил.
//
//   CONNECT_URL       https://connect.esepkz.com
//   CONNECT_API_KEY   ключ из voxa-connect/.env
//   CONNECT_INSTANCE  имя инстанса WhatsApp (например «коннект»)

const DEFAULT_URL = 'https://connect.esepkz.com';

function config() {
  return {
    url: (process.env.CONNECT_URL || DEFAULT_URL).replace(/\/+$/, ''),
    key: process.env.CONNECT_API_KEY || '',
    instance: process.env.CONNECT_INSTANCE || '',
  };
}

function isConfigured() {
  const c = config();
  return Boolean(c.key && c.instance);
}

/// Отправка текста в WhatsApp. Возвращает { ok, id } либо { ok: false, error }.
async function sendText(number, text) {
  const c = config();
  if (!isConfigured()) {
    return { ok: false, error: 'connect_not_configured' };
  }
  try {
    const res = await fetch(
      `${c.url}/message/sendText/${encodeURIComponent(c.instance)}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: c.key,
          // Без браузерного UA Cloudflare перед Connect отдаёт 403
          'User-Agent': 'Mozilla/5.0 (compatible; EsepServer/1.0)',
        },
        body: JSON.stringify({ number, text }),
      },
    );
    const data = await res.json().catch(() => ({}));
    if (!res.ok || !data?.key?.id) {
      return { ok: false, error: `connect_${res.status}`, response: data };
    }
    return { ok: true, id: data.key.id };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

module.exports = { sendText, isConfigured };
