const test = require('node:test');
const assert = require('node:assert/strict');
const { readdirSync } = require('node:fs');
const { resolve } = require('node:path');

test('new migrations do not add collisions beyond the existing legacy migration names', () => {
  const legacy = {
    '001': ['001_access.sql', '001_b1_production.sql'],
    '011': ['011_b1_kg_compat.sql', '011_ocr_truck_intake.sql'],
    '012': ['012_atomic_batch_nira.sql', '012_ocr_milling_source.sql'],
    '013': ['013_ocr_milling_labels.sql', '013_sugar_stock_kg_compat.sql'],
  };
  for (const directory of ['migrations', 'migrations/ocr']) {
    const files = readdirSync(resolve(__dirname, '..', directory)).filter(name => /^\d+_.*\.sql$/.test(name));
    const groups = {};
    for (const file of files) (groups[file.split('_')[0]] ??= []).push(file);
    const duplicates = Object.fromEntries(Object.entries(groups).filter(([, names]) => names.length > 1).map(([number, names]) => [number, names.sort()]));
    assert.deepEqual(duplicates, directory === 'migrations' ? legacy : {}, directory + ': new ordinal collision');
  }
});
