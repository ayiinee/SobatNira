import { Injectable } from '@nestjs/common';
import { FACTORY_SCOPE_CTE } from '../auth/access.sql';
import { FactoryAccess } from '../auth/auth.types';
import { DatabaseService, DatabaseSession } from '../database/database.service';
import { Pagination, scopeValues } from '../production/production.dto';
import { queryPage } from '../production/production.repository';
import { EvidenceImage, EvidenceInfo, EvidenceUpload, StoredEvidence } from './evidence.types';

const COLUMNS = `e.id, e.tenant_id AS "tenantId", e.factory_id AS "factoryId", e.document_id AS "documentId",
  e.request_id AS "requestId", e.request_hash AS "requestHash", e.object_key AS "objectKey",
  e.content_type AS "contentType", e.byte_size AS "byteSize", e.sha256, e.width, e.height,
  e.uploaded_by AS "uploadedBy", e.created_at AS "createdAt",
  '/tenants/' || e.tenant_id || '/factories/' || e.factory_id || '/intake-documents/' || e.document_id || '/evidence/' || e.id || '/content' AS "contentPath"`;

export function publicEvidence(row: StoredEvidence): EvidenceInfo {
  return { id: row.id, documentId: row.documentId, contentType: row.contentType, byteSize: row.byteSize,
    sha256: row.sha256, width: row.width, height: row.height, uploadedBy: row.uploadedBy,
    createdAt: row.createdAt, contentPath: row.contentPath };
}

@Injectable()
export class EvidenceRepository {
  constructor(private readonly database: DatabaseService) {}

  async byRequest(tx: DatabaseSession, access: FactoryAccess, documentId: string, requestId: string) {
    const result = await tx.query<StoredEvidence>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT ${COLUMNS} FROM sobatnira.intake_evidence e JOIN authorized_scope scope
        ON scope."tenantId" = e.tenant_id AND scope."factoryId" = e.factory_id
      WHERE e.document_id = $4::uuid AND e.request_id = $5::uuid`, [...scopeValues(access), documentId, requestId]);
    return result.rows[0];
  }

  request(access: FactoryAccess, documentId: string, requestId: string) {
    return this.byRequest(this.database, access, documentId, requestId);
  }

  async stored(access: FactoryAccess, documentId: string, id: string) {
    const result = await this.database.query<StoredEvidence>(`WITH ${FACTORY_SCOPE_CTE}
      SELECT ${COLUMNS} FROM sobatnira.intake_evidence e JOIN authorized_scope scope
        ON scope."tenantId" = e.tenant_id AND scope."factoryId" = e.factory_id
      WHERE e.document_id = $4::uuid AND e.id = $5::uuid`, [...scopeValues(access), documentId, id]);
    return result.rows[0];
  }

  async insert(tx: DatabaseSession, access: FactoryAccess, documentId: string, id: string, key: string,
    input: EvidenceUpload, hash: string, image: EvidenceImage) {
    await tx.query(`INSERT INTO sobatnira.intake_evidence
      (id, tenant_id, factory_id, document_id, request_id, request_hash, object_key, content_type,
        byte_size, sha256, width, height, uploaded_by)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)`,
    [id, access.tenantId, access.factoryId, documentId, input.requestId, hash, key,
      image.contentType, image.byteSize, image.sha256, image.width, image.height, access.userId]);
  }

  attach(tx: DatabaseSession, access: FactoryAccess, documentId: string, id: string, revision: number) {
    return tx.query(`UPDATE sobatnira.intake_documents SET evidence_id = $4, current_revision = $5, updated_at = clock_timestamp()
      WHERE tenant_id = $1 AND factory_id = $2 AND id = $3`, [access.tenantId, access.factoryId, documentId, id, revision]);
  }

  holdUpload(tx: DatabaseSession, key: string) {
    return tx.query('SELECT pg_advisory_xact_lock(hashtextextended($1::text, 0))', [key]);
  }

  async referenced(key: string): Promise<boolean> {
    // Wait for an ambiguous COMMIT before taking a fresh visibility snapshot.
    // Only the upload attempt that generated this immutable key can claim it.
    return this.database.transaction(async (tx) => {
      await this.holdUpload(tx, key);
      const result = await tx.query('SELECT id FROM sobatnira.intake_evidence WHERE object_key = $1', [key]);
      return result.rows.length > 0;
    });
  }

  async list(access: FactoryAccess, documentId: string, page: Pagination) {
    const result = await queryPage<StoredEvidence>(this.database, `${FACTORY_SCOPE_CTE}, filtered AS (
      SELECT ${COLUMNS} FROM sobatnira.intake_evidence e JOIN authorized_scope scope
        ON scope."tenantId" = e.tenant_id AND scope."factoryId" = e.factory_id WHERE e.document_id = $4::uuid
    )`, [...scopeValues(access), documentId], page, '"createdAt" DESC, id');
    return { ...result, items: result.items.map(publicEvidence) };
  }
}
