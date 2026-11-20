async (page, { origin, output }) => {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setTimezoneOverride', { timezoneId: 'Asia/Jakarta' });
  await page.setViewportSize({ width: 418, height: 966 });
  const requests = new Set();
  page.on('request', request => {
    const url = new URL(request.url());
    if (['http:', 'https:'].includes(url.protocol)) requests.add(url.origin);
  });
  const html = await page.goto(origin);
  const policy = await html.headerValue('content-security-policy');
  if (!policy?.includes("connect-src 'self'") || !policy.includes("font-src 'self'")) {
    throw new Error('Gateway web harus membatasi koneksi dan font ke origin yang sama.');
  }
  const button = name => page.getByRole('button', { name, exact: typeof name === 'string' });
  const scroll = async delta => {
    await page.mouse.move(209, 472);
    await page.mouse.wheel(0, delta);
  };
  const field = async (name, value) => {
    const control = page.getByRole('textbox', { name, exact: true });
    await control.click({ timeout: 15_000 });
    if (name.startsWith('Tanggal kedatangan') || name.startsWith('Waktu penggilingan')) {
      await page.keyboard.press('ControlOrMeta+A');
      await page.keyboard.insertText(value);
    } else {
      await control.fill(value, { timeout: 15_000 });
    }
  };
  const submit = async (label, suffix, status) => {
    const posting = page.waitForResponse(response =>
      response.request().method() === 'POST' && new URL(response.url()).pathname.endsWith(suffix),
    { timeout: 30_000 });
    const [response] = await Promise.all([posting, button(label).click()]);
    if (response.status() !== status) {
      throw new Error(`${suffix} merespons ${response.status()}, diharapkan ${status}.`);
    }
  };
  const expectText = (text, marker) => {
    if (!text.includes(marker)) throw new Error(`Teks layar tidak memuat "${marker}".`);
  };
  const capture = name => page.screenshot({ path: `${output}/${name}.png` });
  const validateIntake = async lot => {
    await scroll(3000);
    await button('Validasi revisi ini').click({ timeout: 15_000 });
    await button(new RegExp(`OCR-${lot}-UJI`)).click();
    await submit('Sahkan dan catat stok', '/validate', 200);
  };

  await page.getByRole('button', { name: 'Enable accessibility' }).dispatchEvent('click', { timeout: 30_000 });
  await button('Masuk').click();
  await field('Email', 'admin@example.invalid');
  await field('Kata sandi', 'sobatnira-demo');
  await button('Masuk').click();
  await button('Pengaturan').click({ timeout: 30_000 });
  await button('Pekerjaan').click({ timeout: 30_000 });
  await button(/Nota Kedatangan Truk Operator/).click();
  await validateIntake('A');

  await button('Kembali').click();
  await button('Menunggu validasi').click();
  await page.getByRole('menuitem', { name: 'Perlu tinjauan manual' }).click();
  await button(/Nota belum dikenali/).click();
  for (const [name, value] of [
    ['Tanggal kedatangan (YYYY-MM-DD)', '2026-11-16'],
    ['Pemasok', 'PEMASOK DEMO'],
    ['Berat bersih (kg)', '1250'],
    ['Jenis tebu', 'BL'],
    ['Catatan pemeriksaan foto', 'Pemeriksaan foto nota sintetis'],
  ]) await field(name, value);
  await button('Simpan draf manual').click();
  await page.getByText('Status: PENDING_VALIDATION', { exact: true }).waitFor({ timeout: 15_000 });
  await validateIntake('B');

  await button('Kembali').click();
  await button('Perlu tinjauan manual').click();
  await page.getByRole('menuitem', { name: 'Menunggu validasi' }).click();
  await button(/Nota Produksi Operator/).click();
  await page.getByText('Nota Produksi', { exact: true }).waitFor();
  await scroll(15000);
  await button('Validasi revisi ini').click({ timeout: 15_000 });
  for (const [lot, liters] of [['A', '90'], ['B', '85']]) {
    await page.getByText(`Penggilingan DEMO-${lot}`, { exact: true }).waitFor();
    await button(new RegExp(`OCR-${lot}-UJI`)).click();
    await field('Total nira hasil giling (L)', liters);
    await field('Waktu penggilingan dan zona waktu', '2026-11-16T09:00:00+07:00');
    if (lot === 'A') await button('Gunakan data penggilingan').click();
    else await submit('Gunakan data penggilingan', '/validate', 200);
  }

  await button('Kembali').click();
  await button('Kembali').click();
  await button('Kloter').click();
  await button(/OCR-A-UJI/).click();
  await scroll(1800);
  await button('Tambah batch').click({ timeout: 15_000 });
  for (const [name, value] of [
    ['Kode batch', 'SMOKE-UJI'], ['Nomor wajan', '1'], ['Waktu pemasakan', '2026-11-16T10:00:00+07:00'],
    ['Volume nira (mL)', '40000'], ['Hasil fisik (kg)', '26'], ['Grade', 'A'], ['Berat grade (kg)', '25'],
    ['Harga per kg (Rp)', '20000'],
  ]) await field(name, value);
  await submit('Simpan', '/production/batches', 201);
  await button('Isi biaya kloter').click();
  for (const [name, value] of [
    ['Biaya tebu (Rp)', '100000'], ['Biaya operasional (Rp)', '20000'],
    ['Biaya bahan (Rp)', '5000'], ['Biaya lain (Rp)', '0'],
  ]) await field(name, value);
  await submit('Simpan', '/costs', 200);
  await submit('Reservasi nira', '/juice/reservations', 201);
  await button('Validasi').click();
  await submit('Konfirmasi', '/approve', 200);
  await button('Kembali').click();

  await button('Laporan').click();
  await page.getByText('25 kg', { exact: true }).first().waitFor({ timeout: 15_000 });
  await capture('laporan');
  await button('Margin').click();
  await page.getByText('Rp375.000', { exact: true }).first().waitFor({ timeout: 15_000 });
  const margin = await page.locator('body').ariaSnapshot();
  expectText(margin, 'Margin sementara');
  await button('Kloter').click();
  await button(/OCR-A-UJI/).click();
  await button(/SMOKE-UJI/).first().waitFor({ timeout: 15_000 });
  const detail = await page.locator('body').ariaSnapshot();
  for (const marker of ['Batch kloter', '90 L', 'SMOKE-UJI']) expectText(detail, marker);
  await capture('detail-kloter');
  await button(/Data tebu dan penggilingan/).first().click();
  const photo = page.getByRole('img', { name: 'Buka pratinjau nota sah' });
  await photo.waitFor();
  await button('Penggilingan').click();
  await photo.waitFor();
  await button('Pengaturan').click();
  await button('Identitas pabrik').waitFor();
  await capture('pengaturan');

  await button('Beranda').click();
  await button('Rekap').click();
  await page.getByText('Total gula final', { exact: true }).waitFor({ timeout: 20_000 });
  await page.getByText('25 kg', { exact: true }).first().waitFor({ timeout: 20_000 });
  const [download] = await Promise.all([
    page.waitForEvent('download', { timeout: 20_000 }),
    button('Simpan PDF').click(),
  ]);
  await download.saveAs(`${output}/rekap.pdf`);
  if (requests.size !== 1 || !requests.has(origin)) {
    throw new Error(`Origin browser berbeda dari acceptance: ${[...requests].join(', ')}`);
  }
  return {
    origin,
    timezone: await page.evaluate(() => Intl.DateTimeFormat().resolvedOptions().timeZone),
    notesValidated: 3,
    grade: 'A',
    publishedPhotos: ['penerimaan', 'penggilingan'],
  };
}
