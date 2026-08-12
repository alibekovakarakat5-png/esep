// Серверное хранение режима интерфейса (ИП/ТОО/Бухгалтер).
// Режим — часть профиля users.user_mode; PATCH /api/auth/mode принимает
// только известные значения, auth-ответы (login/me) отдают userMode.
const test = require('node:test');
const assert = require('node:assert');

const { isValidUserMode, USER_MODES } = require('../src/routes/auth');

test('валидные режимы — ровно ip/too/accountant', () => {
  assert.deepStrictEqual([...USER_MODES].sort(), ['accountant', 'ip', 'too']);
  for (const m of USER_MODES) assert.ok(isValidUserMode(m), m);
});

test('мусор, пустота и null — невалидны', () => {
  for (const bad of ['admin', 'IP', '', null, undefined, 42]) {
    assert.strictEqual(isValidUserMode(bad), false, String(bad));
  }
});
