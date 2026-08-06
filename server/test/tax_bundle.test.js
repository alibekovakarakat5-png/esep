// Стережёт синхронность esep-landing/tax-core.js с исходником services/tax:
// пересобирает бандл во временный файл и сравнивает побайтово с закоммиченным.
// Упал — значит правили services/tax без пересборки: npm run build:tax-core.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { buildTaxCore, DEFAULT_OUTFILE } = require('../scripts/build_tax_core');

test('bundle: tax-core.js лендинга совпадает с пересборкой из services/tax', async () => {
  assert.ok(
    fs.existsSync(DEFAULT_OUTFILE),
    `нет ${DEFAULT_OUTFILE} — запусти: npm run build:tax-core`,
  );
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tax-core-'));
  const tmpFile = path.join(tmpDir, 'tax-core.js');
  try {
    await buildTaxCore(tmpFile);
    const committed = fs.readFileSync(DEFAULT_OUTFILE, 'utf8');
    const rebuilt = fs.readFileSync(tmpFile, 'utf8');
    assert.strictEqual(
      committed,
      rebuilt,
      'tax-core.js разъехался с services/tax — пересобери: npm run build:tax-core',
    );
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});
