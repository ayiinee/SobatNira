import { createApplication } from './application';
import { BACKEND_CONFIG, BackendConfig, ConfigurationError } from './config/backend.config';

async function bootstrap() {
  const app = await createApplication();
  const config = app.get<BackendConfig>(BACKEND_CONFIG);
  await app.listen(config.port, config.host);
}

void bootstrap().catch((error: unknown) => {
  console.error(error instanceof ConfigurationError ? error.message : 'API gagal dimulai; periksa host, port dan konfigurasi.');
  process.exitCode = 1;
});
