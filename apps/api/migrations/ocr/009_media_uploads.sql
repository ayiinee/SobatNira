-- Uploading is external I/O: track it before attaching media in a short transaction.
-- Unattached rows are reconciliation candidates, not permission to delete objects.
CREATE TABLE media_uploads (
  object_key text PRIMARY KEY CHECK (object_key ~ '^[a-f0-9]{64}$'),
  factory_id uuid NOT NULL,
  mime_type text NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png')),
  size_bytes integer NOT NULL CHECK (size_bytes > 0),
  sha256 text NOT NULL CHECK (sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  attached_asset_id uuid UNIQUE REFERENCES media_assets(id),
  attached_at timestamptz,
  CHECK ((attached_asset_id IS NULL) = (attached_at IS NULL))
);
CREATE INDEX media_uploads_unattached_idx ON media_uploads (last_attempt_at, object_key)
  WHERE attached_asset_id IS NULL;
ALTER TABLE media_uploads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON media_uploads FROM PUBLIC, anon, authenticated;
