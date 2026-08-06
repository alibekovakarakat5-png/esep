// Tax Core — единственный источник налоговой математики НК РК 2026 на Node.
// Спека: docs/superpowers/specs/2026-08-06-tax-core-node-design.md
//
// Потребители:
//   - Platform API (income_limit.js и далее) — прямой require
//   - POST /api/tax/calculate — HTTP-обёртка (волна 4)
//   - esep-landing/tax-core.js — esbuild-бандл из calc.js + rates.js (волна 3)
//
// calc.js — чистые функции (ставки первым аргументом), rates.js — дефолты и
// загрузка из tax_config, form910.js — формирование формы 910 (XML/JSON).

const rates = require('./rates');
const calc = require('./calc');
const form910 = require('./form910');

module.exports = {
  ...rates,
  ...calc,
  ...form910,
};
