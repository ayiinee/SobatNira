import { Database } from './database';
import { MediaStorage } from './media';

export async function reconcileMedia(db: Database, media: MediaStorage, remove = false) {
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const result = { candidates: 0, removed: 0, mode: remove ? 'cleanup' : 'report' };
  for await (const object of media.originals()) {
    if (object.modified > cutoff) continue;
    await db.transaction(async tx => {
      // Same lock as intake preparation/attachment; manifests protect external uploads.
      await tx.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', ['sobatnira:media:' + object.key]);
      const refs = await tx.query(`SELECT 1 FROM media_assets WHERE object_key=$1
        UNION ALL SELECT 1 FROM media_uploads WHERE object_key=$1 LIMIT 1`, [object.key]);
      if (refs.rows.length) return;
      result.candidates++;
      if (remove && await media.removeOldOriginal(object.key, cutoff)) result.removed++;
    });
  }
  return result;
}

if (require.main === module) {
  const db = new Database(), media = new MediaStorage();
  if (process.argv.slice(2).some(a => a !== '--delete')) throw new Error('Gunakan tanpa argumen untuk laporan, --delete untuk cleanup.');
  reconcileMedia(db, media, process.argv.includes('--delete')).then(r => console.log(JSON.stringify(r)))
    .catch(() => { console.error('Rekonsiliasi gagal; periksa database dan storage.'); process.exitCode = 1; })
    .finally(async () => { await db.onModuleDestroy(); media.onModuleDestroy(); });
}
