function evidenceRequests(fixture) {
  const upload = async (documentId, bytes, { requestId, expectedRevision = 1, reason = 'Foto bukti sintetis',
    mime = 'image/png', token = 'fixture-admin', filename = '../../untrusted-name.html', extra = {} } = {}) => {
    const form = new FormData();
    form.set('requestId', requestId);
    form.set('expectedRevision', String(expectedRevision));
    form.set('reason', reason);
    for (const [key, value] of Object.entries(extra)) form.set(key, value);
    if (bytes !== undefined) form.set('file', new Blob([bytes], { type: mime }), filename);
    const response = await fetch(`${fixture.base}${fixture.root}/intake-documents/${documentId}/evidence`, {
      method: 'POST', headers: token ? { Authorization: `Bearer ${token}` } : {}, body: form,
    });
    return { status: response.status, body: await response.json() };
  };
  const content = (path, token = 'fixture-admin') => fetch(fixture.base + path, {
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), Origin: 'http://localhost:8080' },
  });
  return { upload, content };
}
module.exports = { evidenceRequests };
