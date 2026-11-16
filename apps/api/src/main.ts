import { createApplication } from './application';
import { BACKEND_CONFIG, BackendConfig, ConfigurationError } from './config/backend.config';
import { validateRuntime } from './documents/config';
import { assertR2Privacy } from './documents/media';

async function bootstrap() {
  validateRuntime();
  if (process.env.SOBATNIRA_MODE === 'connected' && process.env.R2_PUBLIC_BASE_URL) await assertR2Privacy();
  const app = await createApplication();
  const config = app.get<BackendConfig>(BACKEND_CONFIG);
  await app.listen(config.port, config.host);
}

void bootstrap().catch((error: unknown) => {
  console.error(error instanceof ConfigurationError ||
    (error instanceof Error && /^(NestJS|PostgreSQL|FastAPI|Supabase|R2|Mode local):/.test(error.message))
    ? error.message : 'API gagal dimulai; periksa host, port dan konfigurasi.');
  process.exitCode = 1;
});
