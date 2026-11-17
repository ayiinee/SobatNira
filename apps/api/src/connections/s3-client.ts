import { S3Client } from '@aws-sdk/client-s3';

export function s3Send<T>(client: S3Client, command: unknown, options?: unknown): Promise<T> {
  return (client as unknown as { send(command: unknown, options?: unknown): Promise<T> }).send(command, options);
}
