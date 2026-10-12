'use strict';

// Node 20 does not expand quoted globs for --test. Enumerate explicitly so
// Windows, Linux CI and local Node versions run the same set of files.
const { readdirSync } = require('node:fs');
const { join, resolve } = require('node:path');
const { spawnSync } = require('node:child_process');

function testFiles(directory) {
  return readdirSync(directory, { withFileTypes: true })
    .filter(entry => entry.isFile() && entry.name.endsWith('.test.js'))
    .map(entry => join(directory, entry.name))
    .sort();
}

if (require.main === module) {
  const cwd = resolve(__dirname, '..');
  const files = testFiles(join(cwd, 'test'));
  if (!files.length) {
    console.error('No server tests found; refusing an empty green run.');
    process.exitCode = 1;
  } else {
    const result = spawnSync(process.execPath, ['--test', ...files], {
      cwd, stdio: 'inherit', shell: false,
    });
    if (result.error) console.error(result.error.message);
    process.exitCode = result.status ?? 1;
  }
}

module.exports = { testFiles };
