import assert from 'node:assert/strict';
import { readFile, realpath } from 'node:fs/promises';
import { join } from 'node:path';

const files = ['acceptance.json', 'rekap.txt'];

async function compare(first, second) {
  assert.ok(first && second, 'Gunakan node scripts/compare-acceptance.mjs <direktori A> <direktori B>.');
  const [left, right] = await Promise.all([realpath(first), realpath(second)]);
  assert.notEqual(left, right, 'Berikan direktori dari dua putaran yang berbeda.');
  for (const name of files) {
    const [a, b] = await Promise.all([left, right].map(path => readFile(join(path, name), 'utf8')));
    if (name === 'acceptance.json') {
      const [aData, bData] = [JSON.parse(a), JSON.parse(b)];
      assert.equal(aData.version, 1, 'Versi bukti acceptance tidak didukung.');
      assert.ok(aData.checks.includes('pdf'), 'Bukti acceptance belum selesai.');
      assert.deepEqual(aData, bData, 'Hasil browser, ledger, hak akses, atau laporan berbeda.');
    } else {
      assert.ok(a.trim());
      assert.equal(a.replace(/\r\n/g, '\n'), b.replace(/\r\n/g, '\n'), 'Isi PDF Rekap berbeda.');
    }
  }
  console.log('Dua putaran menghasilkan bukti acceptance dan isi PDF Rekap yang sama.');
}

try { await compare(...process.argv.slice(2)); }
catch (error) { console.error(error.message); process.exitCode = 1; }
