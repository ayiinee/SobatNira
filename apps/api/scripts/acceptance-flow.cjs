async (page, { origin, output }) => {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setTimezoneOverride', { timezoneId: 'Asia/Jakarta' });
  await page.clock.setFixedTime(new Date('2026-11-23T12:00:00+07:00'));
  await page.setViewportSize({ width: 418, height: 966 });
  const requests = new Set();
  const blockedFonts = [];
  await page.exposeFunction('recordBlockedFont', url => blockedFonts.push(url));
  await page.addInitScript(() => {
    document.addEventListener('securitypolicyviolation', event => {
      if (event.violatedDirective === 'font-src' || event.blockedURI.includes('fonts.gstatic.com')) {
        window.recordBlockedFont(event.blockedURI);
      }
    });
  });
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
    const control = name === 'ID ekspor'
      ? page.getByRole('textbox', { name: /^ID ekspor(?:\s|$)/ })
      : page.getByRole('textbox', { name, exact: true });
    if (name === 'Catatan pemeriksaan foto') {
      await scroll(1800);
      await control.scrollIntoViewIfNeeded();
      await control.click({ timeout: 15_000 });
      await control.fill(value);
      await waitForText(`${1000 - value.length} characters remaining`);
    } else {
      await control.click({ timeout: 15_000 });
      await page.waitForTimeout(120);
      await page.keyboard.press('ControlOrMeta+A');
      await page.keyboard.type(value, { delay: 24 });
    }
    if (await control.inputValue() !== value) throw new Error('Input was not retained: ' + name);
  };
  const submit = async (label, suffix, status) => {
    const posting = page.waitForResponse(response =>
      response.request().method() === 'POST' && new URL(response.url()).pathname.endsWith(suffix),
    { timeout: 30_000 });
    const [response] = await Promise.all([posting, button(label).click()]);
    if (response.status() !== status) {
      throw new Error(`${suffix} merespons ${response.status()}, diharapkan ${status}.`);
    }
    return response;
  };
  const expectText = (text, marker) => {
    if (!text.includes(marker)) throw new Error(`Teks layar tidak memuat "${marker}".`);
  };
  const waitForText = async (marker, timeout = 15_000) => {
    const deadline = Date.now() + timeout;
    const body = page.locator('body');
    let snapshot = await body.ariaSnapshot();
    while (!snapshot.includes(marker) && Date.now() < deadline) {
      await page.waitForTimeout(200);
      snapshot = await body.ariaSnapshot();
    }
    expectText(snapshot, marker);
    return snapshot;
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
  await button(/Menunggu validasi$/).click();
  await page.getByRole('menuitem', { name: 'Perlu tinjauan manual' }).click();
  await button(/Nota belum dikenali/).click();
  for (const [name, value] of [
    ['Tanggal kedatangan (YYYY-MM-DD)', '2026-11-16'],
    ['Pemasok', 'PEMASOK DEMO'],
    ['Berat bersih (kg)', '1250'],
    ['Jenis tebu', 'BL'],
    ['Catatan pemeriksaan foto', 'Pemeriksaan foto nota sintetis'],
  ]) await field(name, value);
  const savedDraft = await submit('Simpan draf manual', '/manual-draft', 200);
  if (savedDraft.request().postDataJSON().note !== 'Pemeriksaan foto nota sintetis') {
    throw new Error('Catatan pemeriksaan foto tidak terkirim dari formulir.');
  }
  await page.getByText('Status: PENDING_VALIDATION', { exact: true }).waitFor({ timeout: 15_000 });
  await validateIntake('B');

  await button('Kembali').click();
  await button(/Perlu tinjauan manual$/).click();
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
    ['Volume nira (mL)', '40000'], ['Hasil fisik (kg)', '25'], ['Grade', 'A'], ['Berat grade (kg)', '25'],
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
  await waitForText('Gula final 25 kg');
  await button('Ekspor laporan').waitFor();
  await capture('laporan');
  await button('Margin').click();
  const margin = await waitForText('Margin Produksi Rp375.000');
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
  await waitForText('Total gula final 25 kg', 20_000);
  const [download] = await Promise.all([
    page.waitForEvent('download', { timeout: 20_000 }),
    button('Simpan PDF').click(),
  ]);
  await download.saveAs(`${output}/rekap.pdf`);

  await button('Kembali').click();
  await button('Pengaturan').click();
  await scroll(1800);
  await button('Keluar').click();
  await field('Email', 'owner@example.invalid');
  await field('Kata sandi', 'sobatnira-demo');
  await button('Masuk').click();
  await button('Laporan').click();
  await button('Ekspor laporan').click();
  await button('Pilih periode ekspor').click();
  await button(/^Tahun ini /).click();
  const created = await submit('Buat laporan', '/report-exports', 202);
  const { id } = await created.json();
  await waitForText('File siap diunduh', 30_000);
  await button('Kembali').click();
  await button('Ekspor laporan').click();
  await field('ID ekspor', ` ${id} `);
  await button('Cek status').click();
  await waitForText('File siap diunduh');
  for (const [format, signature] of [['pdf', '25504446'], ['xlsx', '504b0304']]) {
    const [file, response] = await Promise.all([
      page.waitForEvent('download', { timeout: 20_000 }),
      page.waitForResponse(item => new URL(item.url()).pathname.endsWith(`/files/${format}`)),
      button(`Unduh ${format.toUpperCase()}`).click(),
    ]);
    if (!response.ok() || (await response.body()).subarray(0, 4).toString('hex') !== signature) {
      throw new Error(`File ekspor ${format} tidak valid.`);
    }
    if (!file.suggestedFilename().endsWith(`.${format}`)) throw new Error('Ekstensi unduhan tidak sesuai.');
    await file.saveAs(`${output}/owner-flutter.${format}`);
  }
  await capture('ekspor-owner');
  if (requests.size !== 1 || !requests.has(origin)) {
    throw new Error(`Origin browser berbeda dari acceptance: ${[...requests].join(', ')}`);
  }
  if (blockedFonts.length) throw new Error(`Font keluar dari origin lokal: ${blockedFonts.join(', ')}`);
  return {
    origin,
    timezone: await page.evaluate(() => Intl.DateTimeFormat().resolvedOptions().timeZone),
    notesValidated: 3,
    grade: 'A',
    publishedPhotos: ['penerimaan', 'penggilingan'],
    ownerDownloads: ['pdf', 'xlsx'],
  };
}
