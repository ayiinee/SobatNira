import { ConfigurationError, loadConfiguration } from '../config/backend.config';
import { checkConnections } from './connection-checks';

async function main() {
  const results = await checkConnections(loadConfiguration());
  if (process.argv.includes('--json')) {
    console.log(JSON.stringify({ status: results.every((result) => result.status === 'ok') ? 'ok' : 'failed', checks: results }, null, 2));
  } else {
    for (const result of results) {
      console.log(`${result.service}: ${result.status} (${result.durationMs} ms) - ${result.message}`);
    }
  }
  if (results.some((result) => result.status !== 'ok')) process.exitCode = 1;
}

void main().catch((error: unknown) => {
  console.error(error instanceof ConfigurationError ? error.message : 'Pemeriksaan koneksi gagal dijalankan.');
  process.exitCode = 1;
});
