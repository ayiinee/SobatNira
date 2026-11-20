// libpng can decode the first frame of APNG without reporting metadata.pages.
// Inspect chunk types rather than scanning compressed pixels for a string.
export function pngHasAnimation(bytes: Buffer) {
  if (!bytes.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))) return false;
  for (let offset = 8; offset + 12 <= bytes.length;) {
    const length = bytes.readUInt32BE(offset);
    if (length > bytes.length - offset - 12) return false; // Full decoder rejects malformed PNG.
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    if (type === 'acTL') return true;
    if (type === 'IEND') return false;
    offset += length + 12;
  }
  return false;
}
