export const MAX_EVIDENCE_BYTES = 8 * 1024 * 1024;
export const MAX_EVIDENCE_PIXELS = 20_000_000;
export interface EvidenceFile { buffer: Buffer; mimetype: string; size: number }
export interface EvidenceImage {
  bytes: Buffer; contentType: string; extension: string; byteSize: number; sha256: string; width: number; height: number;
}
export interface EvidenceInfo {
  id: string; documentId: string; contentType: string; byteSize: number; sha256: string;
  width: number; height: number; uploadedBy: string; createdAt: Date | string; contentPath: string;
}
export interface StoredEvidence extends EvidenceInfo {
  tenantId: string; factoryId: string; requestId: string; requestHash: string; objectKey: string;
}
export interface EvidenceUpload { requestId: string; expectedRevision: number; reason: string }
