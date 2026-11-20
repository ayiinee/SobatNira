import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { randomUUID } from 'node:crypto';

const run = promisify(execFile);

export async function runAcceptanceBrowser(origin, output) {
  assert.ok(process.env.npm_execpath, 'Jalankan acceptance browser melalui npm run local:stack.');
  const session = `sobatnira-${randomUUID()}`;
  const args = [process.env.npm_execpath, 'exec', '--yes', '--package=@playwright/cli@0.1.25', '--',
    'playwright-cli', `-s=${session}`, '--raw'];
  const command = (...action) => run(process.execPath, [...args, ...action],
    { cwd: output, timeout: 150_000, windowsHide: true });
  const driver = await readFile(new URL('./acceptance-flow.cjs', import.meta.url), 'utf8');
  const filename = join(output, 'browser-flow.js');
  await writeFile(filename, `async page => (${driver.trim()})(page, ${JSON.stringify({ origin, output })})\n`);
  try {
    await command('open', 'about:blank', '--browser=chrome');
    const { stdout } = await command('run-code', '--filename', filename);
    const result = JSON.parse(stdout.trim());
    assert.equal(result.origin, origin);
    assert.equal(result.timezone, 'Asia/Jakarta');
    return result;
  } catch (error) {
    const snapshot = await command('snapshot').catch(() => null);
    if (snapshot?.stdout) await writeFile(join(output, 'browser-snapshot.txt'), snapshot.stdout);
    await writeFile(join(output, 'browser-error.txt'), [error.message, error.stdout, error.stderr].filter(Boolean).join('\n'));
    throw new Error(`Acceptance browser gagal. Lihat browser-error.txt di ${output}.`);
  } finally {
    await command('close').catch(() => {});
  }
}
