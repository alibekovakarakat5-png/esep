'use strict';

// Amounts are explicit, bounded and unambiguous. Never guess from the first number.
function parseAmount(value) {
  const s = String(value ?? '').trim().toLowerCase().replace(/[\u00a0\u202f]/g, ' ');
  const m = s.match(/^(\d{1,3}(?: \d{3})+|\d+)([.,]\d{1,2})?\s*(тыс\.?|тысяч(?:а|и)?|млн\.?|миллион(?:а|ов)?)?\s*(?:₸|тг\.?|тенге|kzt)?$/u);
  if (!m) return null;
  const scale = /^м/.test(m[3] || '') ? 1e6 : m[3] ? 1e3 : 1;
  const n = Number(m[1].replace(/ /g, '') + (m[2] || '').replace(',', '.')) * scale;
  return Number.isFinite(n) && n > 0 && n <= 1e12 ? Math.round(n * 100) / 100 : null;
}

function textCalculation(text) {
  const s = String(text).trim().toLowerCase();
  const plain = parseAmount(s);
  if (plain !== null) return { kind: 'calc', amount: plain };
  // Only financial questions with exactly one explicit amount. Exclude form/year numbers.
  if (!/(налог|доход|заработ|зарплат|самозанят|упрощ)/u.test(s)) return null;
  const withoutForms = s.replace(/(?:форм[аыуе]|деклараци[яию])\s*№?\s*(?:910|200|300)(?:\.00)?/gu, '')
    .replace(/(?:19|20)\d{2}\s*(?:год[ауе]?|г\.)/gu, '');
  if (/[-−]\s*\d/.test(withoutForms)) return null;
  const amounts = [...withoutForms.matchAll(/\d[\d \u00a0\u202f]*(?:[.,]\d+)?\s*(?:тыс\.?|тысяч(?:а|и)?|млн\.?|миллион(?:а|ов)?)?\s*(?:₸|тг\.?|тенге|kzt)?/gu)];
  if (amounts.length !== 1) return null;
  const token = amounts[0][0].trim();
  const match = amounts[0];
  const before = withoutForms.slice(0, match.index).slice(-1);
  const tokenEnd = match.index + match[0].trimEnd().length;
  const after = withoutForms.slice(tokenEnd, tokenEnd + 1);
  if (/[\p{L}\d+.,-]/u.test(before) || /[\p{L}\d.,]/u.test(after)) return null;
  // An unlabelled form number is not income in a sentence.
  if (/^(?:910|200|300)(?:\.00)?$/.test(token)) return null;
  if (/^(?:19|20)\d{2}$/.test(token)) return null;
  const amount = parseAmount(token);
  if (amount === null) return null;
  // Do not turn numeric fragments of dates, phone numbers or ranges into calculations.
  if (/[\d][/:–—-]|[/:–—-][\d]/.test(withoutForms)) return null;
  return { kind: /самозанят/u.test(s) ? 'self' : /зарплат/u.test(s) ? 'salary' : 'calc', amount };
}

function startTag(payload) {
  if (!payload) return 'direct';
  // Never persist binding tokens, recovery email addresses or arbitrary personal text.
  if (/^bind_/i.test(payload)) return 'bind';
  if (/^reset(?:[_\s]|$)/i.test(payload)) return 'reset';
  return /^[a-zA-Z0-9_-]{1,64}$/.test(payload) ? payload : 'other';
}

module.exports = { parseAmount, textCalculation, startTag };
