// Бот сбора документов у клиентов бухгалтера.
//
// Раз в месяц бухгалтер пишет каждому клиенту «пришлите выписку», потом
// напоминает, потом звонит. На 30 клиентах это половина рабочей недели.
// Здесь мы собираем текст запроса из чеклиста документов, который уже
// хранится в карточке клиента, и отправляем его в WhatsApp через Connect.
//
// Бот представляется КОМПАНИЕЙ Esep: под этим именем несколько направлений
// (кабинет бухфирмы, сервис для платформ, автоматизация, Connect), и клиент
// бухгалтера не должен гадать, кто ему пишет.

/// Телефон в формат WhatsApp: 11 цифр, начинается с 7.
/// Принимает +7…, 8…, 7… и десятизначный номер без кода страны.
function normalizePhone(raw) {
  const digits = String(raw ?? '').replace(/\D/g, '');
  if (!digits) return null;
  if (digits.length === 11 && digits.startsWith('8')) return '7' + digits.slice(1);
  if (digits.length === 11 && digits.startsWith('7')) return digits;
  if (digits.length === 10) return '7' + digits;
  return digits;
}

/// Собирает запрос документов по клиенту.
/// Возвращает { text, number, missing } либо { text: null, reason }.
function buildDocRequest(client = {}, opts = {}) {
  const number = normalizePhone(client.phone);
  if (!number) return { text: null, number: null, reason: 'no_phone' };

  const missing = (Array.isArray(client.checklist) ? client.checklist : [])
    .filter((d) => d && !d.received)
    .map((d) => String(d.label || '').trim())
    .filter(Boolean);

  if (!missing.length) {
    return { text: null, number, reason: 'all_received' };
  }

  const from = opts.firmName ? opts.firmName : 'ваш бухгалтер';

  const text =
    `Здравствуйте, ${client.name}!\n\n` +
    `Это компания Esep — в нашем сервисе ваш учёт ведёт ${from}.\n\n` +
    `Чтобы закрыть отчётный период, не хватает документов:\n` +
    missing.map((m) => `• ${m}`).join('\n') +
    `\n\nПришлите их прямо сюда, в этот чат — я передам бухгалтеру. ` +
    `Если чего-то из списка у вас нет, напишите об этом, разберёмся.`;

  return { text, number, missing, reason: null };
}

module.exports = { buildDocRequest, normalizePhone };
