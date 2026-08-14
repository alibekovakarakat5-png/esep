// Список origin'ов, которым разрешён доступ к API.
//
// 2026-08-14: формы на buhfirma.esepkz.com и business.esepkz.com не
// отправляли заявки. Причин было две — фронт не слал запрос вовсе, и даже
// если бы слал, браузер получил бы CORS-отказ: этих доменов не было в
// списке. Тест закрепляет домены лендингов, с которых приходят заявки.
//
// Заодно: проверка была `origin.startsWith(allowed)`, из-за чего
// `https://esepkz.com.evil.example` считался своим. Origin — это всегда
// scheme://host:port без пути, поэтому сравнение должно быть точным.
const test = require('node:test');
const assert = require('node:assert');

const { isAllowedOrigin } = require('../src/cors_origins');

test('лендинги, с которых приходят заявки', () => {
  for (const origin of [
    'https://esepkz.com',
    'https://www.esepkz.com',
    'https://app.esepkz.com',
    'https://buhfirma.esepkz.com',
    'https://business.esepkz.com',
    'https://automation.esepkz.com',
  ]) {
    assert.ok(isAllowedOrigin(origin), origin);
  }
});

test('запрос без Origin (curl, сервер-сервер) разрешён', () => {
  assert.ok(isAllowedOrigin(undefined));
  assert.ok(isAllowedOrigin(''));
});

test('чужие домены отклоняются, в том числе похожие на наши', () => {
  for (const origin of [
    'https://evil.example',
    'https://esepkz.com.evil.example',
    'https://buhfirma.esepkz.com.attacker.net',
    'http://esepkz.com',
  ]) {
    assert.strictEqual(isAllowedOrigin(origin), false, origin);
  }
});
