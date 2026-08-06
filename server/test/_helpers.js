const assert = require('node:assert');

const REL_TOL = 1e-9;

function numbersClose(a, b) {
  if (a === b) return true;
  const scale = Math.max(Math.abs(a), Math.abs(b), 1);
  return Math.abs(a - b) <= REL_TOL * scale;
}

// Рекурсивное сравнение с фикстурой: числа — с относительной толерантностью
// 1e-9 (IEEE double даёт шум вида 2975.0000000000005), объекты — со строгим
// совпадением набора ключей, остальное — строгое равенство.
function assertClose(actual, expected, path = '$') {
  if (typeof expected === 'number') {
    assert.strictEqual(typeof actual, 'number', `${path}: ожидалось число, получено ${typeof actual} (${actual})`);
    assert.ok(numbersClose(actual, expected), `${path}: ${actual} != ${expected} (вне толерантности)`);
    return;
  }
  if (expected !== null && typeof expected === 'object') {
    assert.ok(actual !== null && typeof actual === 'object', `${path}: ожидался объект, получено ${actual}`);
    const expKeys = Object.keys(expected).sort();
    const actKeys = Object.keys(actual).sort();
    assert.deepStrictEqual(actKeys, expKeys, `${path}: набор ключей отличается`);
    for (const k of expKeys) assertClose(actual[k], expected[k], `${path}.${k}`);
    return;
  }
  assert.strictEqual(actual, expected, `${path}: ${actual} != ${expected}`);
}

module.exports = { assertClose, numbersClose };
