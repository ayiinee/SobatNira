# Autentikasi dan akses backend

Backend memverifikasi access token melalui Supabase Auth, lalu memeriksa membership tenant/pabrik dan role dari PostgreSQL pada setiap request. Role aplikasi adalah `admin` dan `owner`; owner/manager direpresentasikan dengan `owner`.

## 1. Alur autentikasi

1. Pengguna login melalui Supabase Auth di klien.
2. Klien mengirim access token pada header `Authorization: Bearer <access_token>` ke NestJS.
3. NestJS memanggil `GET /auth/v1/user` dengan token tersebut dan publishable key project.
4. Identitas yang sudah diverifikasi dipakai untuk membaca membership saat ini.
5. Endpoint pabrik memeriksa tenant, pabrik dan role yang disyaratkan sebelum menjalankan handler.

Backend tidak mengambil role bisnis dari JWT yang hanya di-decode, `user_metadata`, `app_metadata`, query, body atau header role buatan klien. Secret key Supabase bukan access token pengguna. Password, token, metadata mentah dan error provider tidak dicetak ke log.

Verifikasi ini mengikuti mekanisme pembacaan pengguna dari Auth server pada [Supabase getUser](https://supabase.com/docs/reference/javascript/auth-getuser). Backend tidak menyediakan endpoint login/password tambahan; pengelolaan sesi dan refresh token tetap menjadi tanggung jawab integrasi Supabase pada klien.

## 2. Model akses

| Tabel | Isi |
| --- | --- |
| `sobatnira.tenants` | Tenant dan status aktif |
| `sobatnira.factories` | Pabrik, tenant pemilik dan status aktif |
| `sobatnira.tenant_memberships` | Hubungan user Supabase dengan tenant dan status aktif |
| `sobatnira.factory_memberships` | Hubungan user dengan pabrik, role `admin`/`owner` dan status aktif |

`user_id` merujuk `auth.users.id`. Composite foreign key mencegah membership menunjuk pabrik dari tenant berbeda atau user yang tidak terdaftar dalam tenant tersebut.

Role berlaku per pabrik. User dapat menjadi admin pada pabrik A dan owner pada pabrik B. Membership tenant saja tidak memberi akses ke semua pabrik; owner juga harus memiliki membership eksplisit pada pabrik yang dituju.

Akses memerlukan seluruh kondisi berikut:

- User memiliki token valid dari project Supabase yang dikonfigurasi.
- Tenant aktif.
- Pabrik aktif dan benar-benar milik tenant pada URL.
- Membership tenant aktif.
- Membership pabrik aktif dan role sesuai endpoint.

Tidak ada cache membership. Penonaktifan atau penurunan role berlaku pada request berikutnya dengan token yang sama. Query daftar anggota juga memeriksa ulang role owner, sehingga konteks guard yang sudah usang tidak cukup untuk membaca daftar tersebut.

Skema aplikasi tidak diberi izin kepada role Supabase `anon`/`authenticated`. RLS diaktifkan pada keempat tabel tanpa policy akses langsung klien. Query aplikasi dijalankan oleh NestJS menggunakan koneksi database backend; karena koneksi ini dapat memiliki hak tinggi, filter identitas dan cakupan pada query tetap wajib.

## 3. Endpoint

| Endpoint | Akses | Respons utama |
| --- | --- | --- |
| `GET /health` | Publik | Status proses NestJS |
| `GET /demo/draft` | Publik untuk development/test; 404 pada production | Fixture sintetis dari FastAPI |
| `GET /auth/me` | Token valid | Identitas dan daftar akses pabrik milik user yang masih aktif |
| `GET /tenants/:tenantId/factories/:factoryId` | Admin/owner pada cakupan tersebut | ID/nama pabrik, tenant dan role user pada pabrik |
| `GET /tenants/:tenantId/factories/:factoryId/memberships` | Owner pada cakupan tersebut | Daftar user ID, role dan status aktif anggota pabrik |

User terautentikasi yang belum memiliki membership menerima `access: []` dari `/auth/me`, lalu ditolak ketika mengakses pabrik.

Endpoint berikut berada di bawah prefix pabrik yang sama. Perubahan memerlukan owner aktif dan dicatat dalam audit.

| Method | Kontrak |
| --- | --- |
| `PATCH /profile` | `version`, `displayCode`, `branchName`, `supportPhone`; kolom opsional bisa diisi `null`. Versi usang mendapat 409. |
| `POST /memberships/admin` | `email`; menambahkan akun Auth yang sudah ada sebagai admin pada pabrik tersebut. Akun baru memerlukan izin undangan Supabase. |
| `PATCH /memberships/:userId` | `isActive` boolean; hanya mengubah membership admin pada pabrik tersebut. |

Untuk uji undangan baru, allowlist URL Flutter Web seperti `https://app.example.invalid/?acceptInvite=1` pada proyek Supabase staging. Di konfigurasi privat NestJS, isi `SUPABASE_ADMIN_INVITE_REDIRECT_URL` dengan URL tersebut dan aktifkan `FACTORY_ADMIN_INVITES_ENABLED` setelah pengelola menyetujui email uji. Pengguna membuka undangan di browser, mengisi kata sandi dan masuk kembali. Secret Supabase hanya digunakan di NestJS. Verifikasi alur email dan login di staging sebelum aktivasi.

Contoh request:

```http
GET /auth/me
Authorization: Bearer <access_token_dari_supabase>
```

Contoh respons sintetis:

```json
{
  "user": { "id": "30000000-0000-4000-8000-000000000001", "email": "owner@example.invalid" },
  "access": [
    {
      "userId": "30000000-0000-4000-8000-000000000001",
      "tenantId": "10000000-0000-4000-8000-000000000001",
      "tenantName": "Tenant Sintetis",
      "factoryId": "20000000-0000-4000-8000-000000000001",
      "factoryName": "Pabrik Sintetis",
      "role": "owner"
    }
  ]
}
```

Kode status:

- `401`: bearer token tidak ada, format salah, tidak valid atau kedaluwarsa.
- `403`: token valid tetapi tenant/pabrik/role tidak diizinkan, atau policy endpoint belum ditetapkan. UUID cakupan yang tidak valid juga ditolak sebagai 403.
- `503`: Supabase Auth/database tidak dikonfigurasi, tidak tersedia, timeout atau mengembalikan respons tidak sesuai kontrak.

Detail tenant/pabrik yang tidak boleh diakses tidak dikembalikan dalam error. Browser dapat melakukan preflight CORS untuk header Authorization tanpa token; request sebenarnya tetap melewati guard.

## 4. Menambahkan endpoint domain

Guard diregistrasikan global melalui `APP_GUARD`. Endpoint baru harus menyatakan kebijakan secara eksplisit; tanpa kebijakan, request ditolak meskipun token valid.

```typescript
@Controller('tenants/:tenantId/factories/:factoryId/documents')
export class DocumentsController {
  @Get()
  @FactoryRoles('admin', 'owner')
  list(@CurrentFactory() access: FactoryAccess) {
    return this.documents.list(access.userId, access.tenantId, access.factoryId);
  }
}
```

Gunakan `@FactoryRoles('owner')` untuk endpoint khusus owner, seperti analitik dan ekspor ketika diimplementasikan. `@IdentityOnly()` ditujukan untuk endpoint identitas seperti `/auth/me`; `@Public()` hanya untuk endpoint yang memang boleh diakses tanpa autentikasi.

Decorator tersedia di `apps/api/src/auth/auth.decorators.ts`. Nama parameter cakupan harus `tenantId` dan `factoryId`. Ambil konteks dari `@CurrentFactory()`, bukan dari body/header klien. Guard tidak otomatis memfilter tabel domain: query dokumen, stok, media atau batch tetap harus menyertakan tenant dan pabrik yang telah diotorisasi. Untuk mutasi, periksa izin dan perubahan data terkait dalam transaksi yang sesuai.

## 5. Migrasi database

Tidak diperlukan variabel rahasia baru. Gunakan `.env` akar repo yang sudah berisi Supabase dan PostgreSQL sesuai [panduan konfigurasi](backend-configuration.md).

Dari `apps/api`:

```powershell
npm run db:migrate
```

Runner menjalankan migrasi berurutan dalam transaksi, menggunakan advisory lock dan checksum. Migrasi yang sudah diterapkan dilewati; file yang sudah diterapkan tetapi diubah ditolak. Checksum menormalisasi CRLF/LF agar konsisten di Windows dan Linux. Migrasi tidak dijalankan otomatis saat API dimulai.

Migrasi pertama menambahkan empat tabel akses dalam skema `sobatnira`. Tabel `sobatnira._migrations` menyimpan riwayat migrasi. Tidak ada seed pengguna atau membership produksi otomatis.

## 6. Menghubungkan owner pertama

Buat akun development melalui dashboard Supabase Auth terlebih dahulu. Salin UUID pengguna dari daftar Users. Tidak perlu membagikan password atau access token.

Operator backend tepercaya dapat menjalankan contoh SQL berikut setelah mengganti UUID user dan kedua nama. Jalankan pada database development melalui SQL Editor atau koneksi administratif. Block ini membuat tenant dan pabrik baru; jalankan sekali untuk onboarding awal, bukan sebagai seed yang diulang.

```sql
DO $$
DECLARE
  v_user_id uuid := 'GANTI_DENGAN_UUID_USER_SUPABASE';
  v_tenant_id uuid := gen_random_uuid();
  v_factory_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO sobatnira.tenants(id, name)
    VALUES (v_tenant_id, 'GANTI_NAMA_TENANT');
  INSERT INTO sobatnira.factories(id, tenant_id, name)
    VALUES (v_factory_id, v_tenant_id, 'GANTI_NAMA_PABRIK');
  INSERT INTO sobatnira.tenant_memberships(tenant_id, user_id)
    VALUES (v_tenant_id, v_user_id);
  INSERT INTO sobatnira.factory_memberships(tenant_id, factory_id, user_id, role)
    VALUES (v_tenant_id, v_factory_id, v_user_id, 'owner');
  RAISE NOTICE 'tenant_id=%, factory_id=%', v_tenant_id, v_factory_id;
END $$;
```

Seluruh block bersifat atomik. UUID yang tidak ada pada Supabase Auth ditolak oleh foreign key. Untuk admin, buat akun Supabase yang terpisah lalu tambahkan membership tenant dan pabrik yang sesuai dengan role `admin` melalui operasi administratif tepercaya. Jangan memberikan fasilitas perubahan membership langsung kepada klien.

Simpan pemetaan akun asli, data tenant/pabrik, token dan kredensial di luar Git. Perubahan role owner tetap melalui operasi administratif tepercaya.

## 7. Verifikasi

Dari `apps/api`:

```powershell
npm test
npm run test:access-db
```

`npm test` menggunakan upstream Auth lokal dan repository sintetis, tanpa memuat `.env` asli. Kasus mencakup token tidak ada/tidak valid, role palsu dalam metadata/header, akses lintas tenant/pabrik, role berbeda antarpabrik, pencabutan akses, policy default menolak, CORS dan gangguan Supabase.

`test:access-db` adalah pemeriksaan integrasi eksplisit menggunakan `.env` asli setelah migrasi. Tes memasukkan user Auth dan data akses sintetis dalam transaksi yang selalu di-rollback, tanpa signup API, undangan atau email. Tes menolak berjalan jika ada trigger aplikasi pada `auth.users` yang belum diperiksa. Query nyata membuktikan filter status aktif, batas role/cakupan, foreign key dan isolasi role browser. Pemeriksaan Supabase nyata menggunakan token tidak valid untuk membuktikan penolakan 401.

Login sukses dengan akun nyata dapat diuji setelah owner pertama dihubungkan. Integrasi UI login Flutter belum menjadi bagian perubahan backend ini; demo fixture development tetap mempertahankan kontrak semula.
