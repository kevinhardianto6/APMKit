# 01 — Kontrak Data & API

**PRD APM Kit** · Dokumen bersama Mobile · Backend · Frontend

> ## ⚠️ Dokumen ini adalah satu-satunya sumber kebenaran
>
> Dokumen tim **tidak boleh menyalin** isi di sini — cukup mereferensikan nomor bagiannya.
> Setiap perubahan wajib melalui review Mobile, Backend, **dan** Frontend, karena ketiganya bergantung pada kontrak ini.
>
> Perubahan yang tidak backward-compatible menaikkan `schema_version`.

---

## 1. Siapa Bergantung pada Apa

| Bagian | Mobile | Backend | Frontend |
|---|:---:|:---:|:---:|
| §2 Envelope | menulis | membaca | — |
| §3 Event | menulis | membaca | — |
| §4 Tipe & atribut | menulis | membaca | menampilkan |
| §5 Enum `failure_category` | menghasilkan | menyimpan | filter & grouping |
| §6 Fingerprinting | — | menghitung | menampilkan sebagai Issue |
| §7 Ingestion API | memanggil | menyediakan | — |
| §8 Symbol API | CI memanggil | menyediakan | status ditampilkan |
| §9 Config API | memanggil | menyediakan | admin mengatur |
| §10 Read API | — | menyediakan | memanggil |

---

## 2. Envelope

Satu request berisi satu envelope. Konteks statis diletakkan di envelope (tidak diulang per event) untuk menghemat bandwidth dan disk.

```json
{
  "schema_version": 1,
  "sdk":     { "name": "apmkit-ios", "version": "1.0.0" },
  "app":     { "id": "com.company.appname", "version": "3.2.1", "build": "1042" },
  "device":  { "os": "iOS", "os_version": "17.4", "model": "iPhone14,2",
               "locale": "id_ID", "timezone": "Asia/Jakarta" },
  "integrity": { "is_emulator": false, "is_rooted": false,
                 "is_dev_mode": false, "debugger_attached": false },
  "install_id": "8f14e45f-ea1a-4f2c-9d3b-7c2a1b0e5d44",
  "session_id": "b3d9c1a2-5e6f-4a7b-8c9d-0e1f2a3b4c5d",
  "user_id":    "client-supplied-string-or-sdk-generated",
  "events": [ /* array of Event */ ]
}
```

| Field | Tipe | Keterangan |
|---|---|---|
| `schema_version` | int | Dinaikkan saat ada breaking change. Backend **wajib menolak** versi yang tidak dikenal dengan `400`. |
| `install_id` | UUID | Identitas instalasi, digenerate saat SDK pertama kali jalan. **Bukan identitas user.** Reset saat app di-uninstall. |
| `session_id` | UUID | Satu sesi = dari app foreground sampai background > 30 detik. |
| `user_id` | string \| null | Identifier yang di-set app host — **string bebas** (boleh nomor telepon, email, user ID internal, atau apa pun). Kalau app host tidak mengisinya, SDK meng-generate ID acak stabil per install. **Dikirim mentah lewat TLS**, lalu di-hash jadi `user_ref` di ingestion (BE-21) — nilai mentah **tidak pernah disimpan**. Lihat §2.1. |
| `integrity` | object | Sinyal environment device, di-snapshot sekali per sesi: `is_emulator`, `is_rooted`, `is_dev_mode`, `debugger_attached` (semua `bool`). Bersifat heuristik (MOB-29..31). Bukan PII. |

### 2.1 Identifier: `user_id` (mentah, transit) → `user_ref` (tersimpan)

Model identifier sengaja dipisah dua, supaya app host bebas memakai identifier apa pun **tanpa** menaruh PII di storage APM:

- **`user_id`** — nilai mentah yang dikirim app (atau di-generate SDK). Boleh berupa nomor telepon/email/teks. Ada di envelope, **transit lewat TLS**, tidak pernah dipersistensi mentah.
- **`user_ref`** — hasil `HMAC-SHA256(server_key, user_id)` yang dihitung backend saat ingestion (BE-21). **Hanya nilai inilah yang disimpan** dan dipakai di seluruh downstream: Issue, sesi, Read API, dashboard. Opaque, tidak bisa dibalik tanpa `server_key` yang hanya ada di server.

Konsekuensinya: input mentah yang sama (mis. nomor telepon yang sama) selalu menghasilkan `user_ref` yang sama → grouping & korelasi per user tetap jalan penuh, tapi storage tidak pernah memuat identitas langsung yang bisa dibaca. Trade-off jujur: nilai mentah **tetap melewati** endpoint ingestion sebelum di-hash-dan-dibuang — klaim yang benar adalah "tidak disimpan", bukan "tidak pernah dikirim".

---

## 3. Event

```json
{
  "event_id": "3f2b1c8a-...",
  "type": "network_failure",
  "ts_client": "2026-07-24T09:12:33.412Z",
  "seq": 1043,
  "attrs": { },
  "ctx": { "connectivity": "wifi", "screen": "CheckoutViewController",
           "app_state": "foreground", "low_power": false }
}
```

| Field | Keterangan |
|---|---|
| `event_id` | UUID v4. **Kunci deduplikasi di backend** — pengiriman bersifat *at-least-once*, event yang sama bisa datang dua kali. |
| `seq` | Counter monotonik per sesi. Dipakai backend untuk mengurutkan event ketika jam device tidak akurat. |
| `ts_client` | Waktu dari device. **Tidak boleh dipercaya sebagai sumber kebenaran** — backend menyimpan `ts_server` terpisah (BE-05). |
| `ctx` | Konteks volatil yang bisa berubah dalam satu sesi. |

---

## 4. Tipe Event & Atribut

### 4.1 `network` — request selesai

| Atribut | Tipe | Wajib |
|---|---|---|
| `host` | string | ✓ |
| `path` | string (sudah dinormalisasi & di-scrub, lihat SEC-03b) | ✓ |
| `method` | string | ✓ |
| `status_code` | int | ✓ |
| `duration_ms` | int | ✓ |
| `dns_ms`, `tcp_ms`, `tls_ms`, `ttfb_ms` | int | — |
| `req_bytes`, `res_bytes` | int | — |
| `protocol` | string (`http/1.1`, `h2`) | — |
| `tls_version` | string | — |
| `reused_connection` | bool | — |

### 4.2 `network_failure` — request gagal

| Atribut | Tipe | Wajib |
|---|---|---|
| `host`, `path`, `method` | string | ✓ |
| `failure_category` | enum (§5) | ✓ |
| `status_code` | int | ✓ jika `failure_category = http_error`, selain itu — |
| `error_domain`, `error_code` | string, int | ✓ untuk kegagalan transport, — untuk `http_error` |
| `underlying_domain`, `underlying_code` | string, int | — |
| `tls_phase_reached` | enum: `none` \| `started` \| `completed` | — |
| `duration_ms` | int | ✓ |

> **Perilaku untuk respons 4xx/5xx (`http_error`).** Respons dengan status ≥ 400 di level client bukan error transport — di iOS muncul sebagai `didCompleteWithError: nil` yang biasa (tak bisa dibedakan dari sukses tanpa SDK memeriksa status), di Android sebagai response biasa. SDK **memeriksa `status_code` di setiap request yang selesai**, lalu:
> 1. Selalu emit event **`network`** dengan `status_code` asli (§4.1) — request-nya memang selesai.
> 2. Jika `status_code ≥ 400`, **tambahan** emit event **`network_failure`** dengan `failure_category = http_error` dan `status_code` terisi (untuk fingerprinting §6).
>
> `http_error` adalah kategori tersendiri, **terpisah** dari kegagalan transport (`ssl_*`, `timeout`, `dns`, `connectivity`). Satu respons 500 = satu `network` + satu `network_failure(http_error)`; **jangan** juga dihitung sebagai kegagalan transport, supaya "network failure rate" per kategori di dashboard tidak tercampur.

### 4.3 `crash`

| Atribut | Keterangan |
|---|---|
| `crash_type` | `signal` \| `exception` \| `anr` \| `hang` |
| `name`, `reason` | Nama exception/signal dan alasannya |
| `is_fatal` | bool |
| `threads` | Array thread dengan stack frame (alamat + offset) |
| `binary_images` | Daftar binary + UUID — **wajib** untuk symbolication |
| `app_state` | State saat crash |
| `time_since_launch_ms` | int |

### 4.4 `error` — dilaporkan manual

| Atribut | Keterangan |
|---|---|
| `name`, `message` | Deskripsi error |
| `domain`, `code` | Untuk NSError/Exception |
| `handled` | Selalu `true` |
| `custom.*` | Key kustom dari developer. Maks 20 key, masing-masing ≤ 256 karakter. |

### 4.5 `breadcrumb`

| Atribut | Keterangan |
|---|---|
| `category` | `navigation` \| `user_action` \| `network` \| `lifecycle` \| `state` \| `log` |
| `message` | Deskripsi singkat |
| `level` | `debug` \| `info` \| `warning` \| `error` |

### 4.6 `lifecycle` / `performance`

| Atribut | Keterangan |
|---|---|
| `state` | `cold_start` \| `warm_start` \| `foreground` \| `background` \| `terminate` |
| `duration_ms` | Untuk cold start: waktu sampai frame pertama |

---

## 5. Enum `failure_category`

Nilai **identik di iOS & Android**. Dipakai untuk grouping dan filter di dashboard.

| Nilai | Arti |
|---|---|
| `ssl_certificate` | Sertifikat server tidak valid, kedaluwarsa, atau root tidak dikenal |
| `ssl_pinning_rejected` | Validasi pinning kustom aplikasi menolak sertifikat |
| `tls_handshake` | Handshake gagal di luar dua kasus di atas |
| `timeout` | Request melewati batas waktu |
| `dns` | Resolusi nama gagal |
| `connectivity` | Tidak ada koneksi atau koneksi terputus di tengah |
| `cancelled` | Dibatalkan aplikasi secara sengaja |
| `http_error` | Response diterima dengan status 4xx/5xx (aturan emit di §4.2) |
| `unknown` | Tidak terpetakan |

> **Catatan implementasi iOS:** validasi pinning kustom yang menolak koneksi umumnya muncul sebagai `NSURLErrorCancelled`, bukan sebagai error SSL. SDK harus membedakannya dari pembatalan biasa dengan menandai request yang gagal di tahap trust evaluation, lalu memetakannya ke `ssl_pinning_rejected`. Tanpa ini, kegagalan pinning tidak akan terlihat sebagai masalah keamanan di dashboard.

---

## 6. Fingerprinting (Grouping)

Backend mengelompokkan event menjadi **Issue**. Website menampilkan Issue, bukan event mentah — tanpa ini dashboard menjadi ribuan baris duplikat.

| Tipe | Aturan fingerprint |
|---|---|
| `crash` | Hash dari (tipe exception + N frame teratas non-sistem yang sudah dinormalisasi) |
| `network_failure` | Hash dari (host + `failure_category` + `status_code`) |
| `error` | Hash dari (domain + code + message yang dinormalisasi: angka & UUID diganti placeholder) |

> **Aturan ini milik Backend, tapi Frontend bergantung padanya.** Mengubah aturan mengubah pengelompokan data historis — perubahan wajib dikomunikasikan dan diberi versi.
>
> Kualitas fingerprint sangat bergantung pada normalisasi path (SEC-03b) yang dilakukan Mobile. Path yang tidak dinormalisasi menghasilkan ribuan Issue unik untuk satu masalah yang sama.

---

## 7. `POST /v1/ingest`

**Headers:** `X-APM-Key` (kunci per app) · `X-APM-Sdk` (nama & versi) · `Content-Type: application/json` · `Content-Encoding: gzip`

**Body:** Envelope (§2). Maksimum **1 MB terkompresi**, maksimum **200 event** per request.

### Kontrak response — wajib disepakati Mobile & Backend

| Kode | Arti | Aksi SDK |
|---|---|---|
| `202` | Diterima & diantrikan | Hapus batch dari disk |
| `400` | Payload malformed / schema tidak dikenal | **Buang batch** — jangan retry selamanya. Catat sebagai metrik internal. |
| `401` / `403` | Kunci tidak valid | Nonaktifkan pengiriman 24 jam, jangan hammer server |
| `413` | Payload terlalu besar | Pecah batch jadi setengah, retry |
| `429` | Rate limited | Backoff sesuai header `Retry-After` |
| `5xx` | Error server | Exponential backoff (30s → 60s → … → maks 30 menit), data tetap di disk |

> Kontrak ini sumber bug klasik kalau tidak disepakati di awal: SDK yang me-retry `400` selamanya akan menghabiskan baterai user dan membanjiri server dengan payload yang memang tidak akan pernah diterima.

**Idempotensi:** backend melakukan dedup berdasarkan `event_id` dengan window minimal **7 hari**.

---

## 8. `POST /v1/symbols`

Upload dari CI, **bukan dari device**. Autentikasi memakai token CI terpisah, bukan kunci app.

**Multipart:** `app_id`, `version`, `build`, `platform`, dan file — dSYM zip (iOS) atau `mapping.txt` (Android).

> **Gate rilis:** pipeline CI harus **gagal** jika upload symbol gagal. Tanpa symbol, crash report tidak terbaca dan datanya praktis hilang — dan baru ketahuan berminggu-minggu kemudian saat ada yang mencoba membaca crash.

---

## 9. `GET /v1/config`

SDK mengambil konfigurasi remote saat startup, dengan cache lokal dan fallback ke default bila gagal.

```json
{ "enabled": true,
  "sampling": { "network": 1.0, "breadcrumb": 1.0 },
  "max_batch": 200,
  "upload_interval_s": 30,
  "disabled_features": [] }
```

`enabled: false` berfungsi sebagai **kill switch** — memungkinkan menonaktifkan SDK di seluruh app tanpa rilis baru. Wajib ada sebelum rollout ke tim lain.

---

## 10. Read API (untuk Website)

Autentikasi **terpisah** dari ingestion — sesi user / SSO, bukan `X-APM-Key`.

| Endpoint | Fungsi |
|---|---|
| `GET /v1/apps` | Daftar app yang boleh diakses user |
| `GET /v1/apps/{id}/overview` | Metrik ringkas + tren |
| `GET /v1/apps/{id}/issues` | Daftar issue (filter, sort, paginasi) |
| `GET /v1/issues/{id}` | Detail issue + stack tersimbolikasi + sample event |
| `GET /v1/issues/{id}/breadcrumbs` | Timeline breadcrumb untuk sample event |
| `GET /v1/apps/{id}/network` | Agregasi network per host & kategori |
| `POST /v1/apps/{id}/users/resolve` | Menerima identifier mentah (mis. nomor telepon/email), meng-hash-nya dengan `server_key`, mengembalikan `user_ref`. **Input tidak disimpan.** Ini yang membuat "cari user via nomor HP" tetap bisa tanpa menyimpan nomornya. |
| `GET /v1/apps/{id}/users/{user_ref}` | Ringkasan user + timeline sesi (layar User Lookup) |
| `PATCH /v1/issues/{id}` | Ubah status (triaged / resolved / ignored) |
| `GET/POST /v1/apps/{id}/alerts` | Konfigurasi alert |

> **Filter device-integrity berlaku lintas endpoint.** Endpoint `overview`, `issues`, dan `network` menerima parameter filter `is_emulator`, `is_rooted`, `is_dev_mode` — termasuk opsi "kecualikan sesi non-real (emulator/debug)" untuk metrik headline (FE-22).

---

## 11. Aturan Perubahan Kontrak

| Jenis perubahan | Contoh | Perlakuan |
|---|---|---|
| **Aditif** | Menambah atribut opsional baru | Tidak menaikkan `schema_version`. Backend abaikan field yang tidak dikenal; Frontend tangani ketiadaannya. |
| **Breaking** | Menghapus/mengganti nama field, mengubah tipe, mengubah arti enum | Naikkan `schema_version`. Backend wajib mendukung versi lama selama masih ada app terpasang yang mengirimkannya. |
| **Enum bertambah nilai** | `failure_category` dapat nilai baru | Aditif, tapi Frontend wajib punya fallback tampilan untuk nilai yang belum dikenal. |

> **Konsekuensi khas mobile:** app versi lama akan tetap terpasang di device user berbulan-bulan setelah rilis baru. Backend tidak bisa berasumsi semua client sudah upgrade — dukungan multi-versi bersifat permanen, bukan sementara.