// Сборка браузерного бандла tax-core.js для лендинга (волна 3 спеки
// docs/superpowers/specs/2026-08-06-tax-core-node-design.md).
//
// Запуск: npm run build:tax-core   (из server/)
//
// Бандлит services/tax целиком (calc + rates + form910) в IIFE с глобалью
// EsepTax. Ставки НК-2026 вшиты как дефолты — лендинг считает без сети.
// Синхронность закоммиченного бандла с исходником стережёт
// test/tax_bundle.test.js (пересборка и побайтовое сравнение).
//
// ⚠ esbuild запинен на 0.27.3: бинарь 0.28.x блокируется Device Guard
// на машине разработчика (проверено 2026-08-06).

const path = require('path');
const esbuild = require('esbuild');

const DEFAULT_OUTFILE = path.join(__dirname, '..', '..', 'esep-landing', 'tax-core.js');

const BANNER = `/*
 * tax-core.js — налоговая математика НК РК 2026 (Esep).
 * СГЕНЕРИРОВАНО из server/src/services/tax — НЕ ПРАВИТЬ РУКАМИ,
 * правки затираются пересборкой: cd server && npm run build:tax-core
 * Ставки вшиты как дефолты: EsepTax.DEFAULT_RATES (версия EsepTax.DEFAULT_VERSION).
 */`;

async function buildTaxCore(outfile = DEFAULT_OUTFILE) {
  return esbuild.build({
    entryPoints: [path.join(__dirname, '..', 'src', 'services', 'tax', 'index.js')],
    bundle: true,
    format: 'iife',
    globalName: 'EsepTax',
    target: ['es2019'],
    banner: { js: BANNER },
    outfile,
    logLevel: 'silent',
  });
}

module.exports = { buildTaxCore, DEFAULT_OUTFILE };

if (require.main === module) {
  buildTaxCore()
    .then(() => {
      const { size } = require('fs').statSync(DEFAULT_OUTFILE);
      console.log(`✅ tax-core.js собран: ${DEFAULT_OUTFILE} (${(size / 1024).toFixed(1)} KB)`);
    })
    .catch((err) => {
      console.error('Сборка tax-core.js упала:', err.message);
      process.exit(1);
    });
}
