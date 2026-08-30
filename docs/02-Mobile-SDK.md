# 02 — Mobile SDK (iOS & Android)

**PRD APM Kit** · Untuk tim Mobile

> Konteks proyek: `00-Overview.md`
> Schema event & kontrak API: `01-Kontrak-Data-API.md` — **jangan disalin ke sini, referensikan saja**

---

## 1. Yang Dibangun Tim Ini

SDK yang di-embed ke aplikasi iOS & Android, bertugas menangkap event, menyimpannya secara lokal, dan mengirimkannya ke backend saat kondisi memungkinkan.

```
┌──────────────────────────────────────────┐
│ Capture Layer                            │
│ network · crash · error manual · crumbs  │
├──────────────────────────────────────────┤
│ Scrubber            ← redaksi PII        │
├──────────────────────────────────────────┤
│ Disk Queue          ← atomic write       │
├──────────────────────────────────────────┤
│ Sync Engine         ← batch + backoff    │
└──────────────────────────────────────────┘
```

**Aturan urutan yang tidak boleh dibalik:** Capture → Scrub → **Disk** → Sync. Penulisan ke disk terjadi sebelum operasi network apa pun. Ini inti dari prinsip *write local first*.

---

## 2. Ketergantungan Lintas Tim

| Yang tim ini **butuhkan** | Dari | Kapan |
|---|---|---|
| Endpoint ingestion aktif (walau minimal) | Backend | M1 |
| Kunci app per aplikasi | Backend | M1 |
| Endpoint `GET /v1/config` untuk kill switch & sampling | Backend | M2 |
| Endpoint upload symbol + integrasi CI | Backend | M3 |

| Yang tim lain **butuhkan** dari tim ini | Untuk | Kapan |
|---|---|---|
| Payload sesuai `01-Kontrak-Data-API.md` §2–4 | Backend | M1 |
| Path yang sudah dinormalisasi (SEC-03b) | Backend — kualitas fingerprinting | M1 |
| `binary_images` + UUID pada crash | Backend — symbolication | M3 |
| `failure_category` konsisten iOS & Android | Frontend — filter & grouping | M2 |
| Flag `integrity` per sesi (emulator/root/dev-mode) | Frontend — filter & exclude sesi non-real | M3 |
| Dokumen data inventory (SEC-21) | Semua tim adopter — pengisian privacy label | M5 |

---

## 3. Requirement Fungsional

> Berlaku untuk kedua platform kecuali ditandai khusus. **Perilaku yang terlihat dari luar — schema, kategorisasi, kontrak response — wajib identik di iOS & Android.**

### 3.1 Network Observability — Fase 1

| ID | Requirement | Prio |
|---|---|---|
| MOB-01 | Menangkap metrik seluruh HTTP request: URL, method, status, durasi, breakdown per fase (DNS/TCP/TLS/TTFB) | P0 |
| MOB-02 | Menangkap kegagalan network dan memetakannya ke `failure_category` (`01` §5) | P0 |
| MOB-02b | Periksa `status_code` tiap request yang selesai: selalu emit event `network`; jika status ≥ 400, tambahan emit `network_failure` dengan `failure_category = http_error` + `status_code` (aturan lengkap `01` §4.2). `http_error` tidak dihitung sebagai kegagalan transport. | P0 |
| MOB-03 | Membedakan penolakan pinning kustom dari pembatalan request biasa | P0 |
| MOB-10 | Traffic SDK sendiri dikecualikan dari instrumentasi (mencegah loop tak berujung) | P0 |

**Catatan implementasi:**
- **iOS:** `URLSessionTaskMetrics` memberi breakdown per fase, termasuk `secureConnectionStartDate`/`EndDate`. Handshake yang dimulai tapi tak pernah selesai = gagal di fase TLS.
- **Android:** pakai `EventListener` OkHttp, bukan hanya `Interceptor`. `EventListener` mengekspos `secureConnectStart`/`secureConnectEnd` dan `callFailed`, sehingga fase kegagalan bisa diketahui.

### 3.2 Penyimpanan Lokal — Fase 1

| ID | Requirement | Prio |
|---|---|---|
| MOB-04 | Menulis setiap event ke disk secara **atomic** sebelum operasi network apa pun | P0 |
| MOB-05 | Antrean bertahan melewati proses mati, force quit, dan device restart | P0 |
| MOB-06 | Batas antrean: maks 20 MB **atau** 5.000 event; eviction FIFO saat penuh | P0 |
| MOB-14 | Scrubbing dijalankan sebelum penulisan ke disk — detail lengkap di §6.1 | P0 |

### 3.3 Pengiriman — Fase 1

| ID | Requirement | Prio |
|---|---|---|
| MOB-07 | Batch dengan retry & exponential backoff sesuai kontrak response (`01` §7) | P0 |
| MOB-08 | Trigger upload: timer periodik, transisi ke background, dan pemulihan koneksi | P0 |
| MOB-09 | Event lokal **hanya dihapus setelah response sukses** dari server | P0 |

> Poin MOB-09 adalah yang membuat jaminan *at-least-once* berlaku. Menghapus sebelum ACK berarti kehilangan data setiap kali koneksi putus di tengah upload.

### 3.4 API untuk Developer — Fase 1

| ID | Requirement | Prio |
|---|---|---|
| MOB-11 | API publik: `logError(error, context)` dan `breadcrumb(message, category)` | P0 |
| MOB-12 | Breadcrumb otomatis untuk **lifecycle app** dan **perubahan konektivitas** (benar-benar otomatis, tanpa aksi app host). Untuk **perpindahan screen**: di iOS bersifat *host-invoked* — SDK menyediakan primitive `recordScreen(_:)` plus helper opt-in (base class UIViewController & view modifier SwiftUI), **tanpa method swizzling**. Di Android perpindahan screen bisa otomatis via `ActivityLifecycleCallbacks`. | P0 |
| MOB-13 | Ring buffer breadcrumb: 100 entri terakhir, dilampirkan ke setiap crash/error | P0 |
| MOB-26 | Mode debug: log lokal berisi event yang tertangkap, non-aktif di build release | P1 |
| MOB-28 | API `setUser(id)` untuk app host menetapkan `user_id` (string bebas). Jika tidak di-set, generate ID acak stabil per install sebagai fallback. `user_id` dikirim mentah di envelope; hashing dilakukan backend (BE-21). | P0 |

> **Kenapa screen tracking di iOS tidak "otomatis" (MOB-12).** Satu-satunya cara membuatnya benar-benar otomatis di iOS adalah *method swizzling* `UIViewController.viewDidAppear`. Itu ditolak: teknik ini mengganti implementasi method sistem saat runtime, berisiko crash/undefined behavior, dan **bentrok dengan SDK lain yang melakukan hal sama** (Firebase Analytics sudah men-swizzle method ini di aplikasi kita). Karena SDK ini dipasang di aplikasi tim lain, kegagalan seperti itu akan dilimpahkan ke kita dan mematikan adopsi (G4) — melanggar batasan mutlak "SDK tidak boleh menjadi penyebab crash aplikasi host".
>
> Konsekuensinya: integrasi screen tracking adalah **satu-satunya langkah yang tidak nol-effort**, jadi harus ditulis menonjol di dokumen integrasi (MOB-25), bukan sebagai catatan kaki. Nama screen berasal dari developer → tetap wajib melewati Scrubber (SEC-05).
>
> **Catatan paritas:** perbedaan iOS vs Android di sini disengaja. Android punya `ActivityLifecycleCallbacks` yang resmi dan aman, jadi di sana screen tracking memang otomatis. Yang wajib identik adalah *output*-nya (event breadcrumb dengan `category: navigation`), bukan cara memicunya.

### 3.5 Crash Reporting — Fase 2

| ID | Requirement | Prio |
|---|---|---|
| MOB-15 | Menangkap uncaught exception dan sinyal native | P0 |
| MOB-16 | Crash report ditulis ke disk saat crash, dikirim pada peluncuran berikutnya | P0 |
| MOB-17 | Menyertakan `binary_images` + UUID untuk symbolication | P0 |
| MOB-18 | Deteksi ANR (Android) / hang main thread > 2 detik (iOS) | P1 |
| MOB-19 | Metrik cold start hingga frame pertama | P1 |

> **Rekomendasi:** bungkus library crash reporting yang sudah matang daripada menulis signal handler sendiri. Menulis kode yang harus berjalan dengan benar saat aplikasi sedang sekarat adalah bagian tersulit dari seluruh proyek ini, dan kesalahannya berdampak langsung ke aplikasi tim lain. Keputusan final: `00-Overview.md` §11 no. 4.

### 3.6 Kontrol Jarak Jauh — Fase 2

| ID | Requirement | Prio |
|---|---|---|
| MOB-20 | Mengambil remote config saat startup, dengan cache & fallback default | P0 |
| MOB-21 | Mematuhi kill switch (`enabled: false`) | P0 |
| MOB-22 | Sampling per tipe event, dikontrol remote config | P1 (naik ke P0 di Fase 3 bila proyeksi volume melebihi kapasitas) |
| MOB-27 | SDK melaporkan kesehatan dirinya sendiri: jumlah event tertulis vs terkirim vs terbuang | P1 |

### 3.7 Distribusi & Dukungan — Fase 1–3

| ID | Requirement | Prio |
|---|---|---|
| MOB-23 | Distribusi via SPM & CocoaPods (iOS), Maven internal (Android) | P0 |
| MOB-24 | Semver + dokumen kompatibilitas; breaking change hanya di major version | P0 |
| MOB-25 | Sample app + dokumen integrasi — target: integrasi selesai < 30 menit | P0 |

### 3.8 Sinyal Integritas Device — Fase 1

Snapshot sekali per sesi saat startup, dilampirkan ke `integrity` di envelope (`01` §2). Karena envelope sudah membawa app version, device model, dan OS version, tiap flag otomatis punya konteks "versi berapa, device & OS apa" — tidak perlu field tambahan.

| ID | Requirement | Prio |
|---|---|---|
| MOB-29 | Deteksi **emulator/simulator** → `integrity.is_emulator`. iOS: `TARGET_OS_SIMULATOR` + cek model/env var. Android: heuristik build props (`FINGERPRINT`, `HARDWARE`=goldfish/ranchu, `MODEL`), file QEMU (`/dev/qemu_pipe`), sensor absen. | P1 |
| MOB-30 | Deteksi **jailbreak/root** → `integrity.is_rooted`. iOS: cek file Cydia/Sileo, kemampuan tulis di luar sandbox, symlink mencurigakan. Android: cek binary `su`, paket Magisk/SuperSU, `test-keys` di build tags, partisi system writable. | P1 |
| MOB-31 | Deteksi **developer mode** → `integrity.is_dev_mode` **dan** `integrity.debugger_attached` sebagai **dua boolean independen** (bukan digabung dengan OR — schema `01` §2 memang menyediakan field terpisah). `debugger_attached`: debugger sedang menempel saat itu — iOS via `sysctl` (`P_TRACED`), Android via `Debug.isDebuggerConnected()`. `is_dev_mode`: environment non-produksi — iOS via build non-App-Store (`embedded.mobileprovision`, TestFlight `sandboxReceipt`), Android via `Settings.Global.DEVELOPMENT_SETTINGS_ENABLED` + `ADB_ENABLED`. | P1 |

> **Kenapa dipisah (MOB-31).** Dua sinyal ini artinya berbeda dan berguna dibedakan saat menyaring sesi non-real: build TestFlight yang dipakai QA bisa berjalan **tanpa** debugger, sementara developer yang sedang nge-debug adalah kasus lain lagi. Menggabungkannya jadi satu OR akan membuang informasi itu dan membuat field `debugger_attached` di schema jadi mubazir.

**Batas keandalan & aturan (wajib dibaca sebelum implementasi):**
- Ketiganya **heuristik dan bisa diakali** — cukup untuk *observability* (menyaring/menandai sesi), **bukan** security gate. iOS simulator ~pasti terdeteksi; Android emulator & root bisa disembunyikan (Magisk DenyList dll.).
- **Jangan pakai API yang butuh permission sensitif.** IMEI/serial di Android sudah dibatasi ketat sejak Android 10 — cukup build props & file check yang tidak butuh permission.
- Flag ini **properti environment device, bukan PII** → aman dengan postur "no direct identifiers". Jangan pernah diikat ke identitas asli.
- **Upgrade path (opsional, bukan v1):** kalau nanti butuh sinyal yang sulit dipalsu (untuk security gate), pakai **Play Integrity API** (Android; SafetyNet Attestation sudah dimatikan Jan 2025) dan **App Attest / DeviceCheck** (iOS) — keduanya hardware-backed, verifikasi di server. Tercatat sebagai open decision di `00-Overview.md` §11.

---

## 4. Batasan Mutlak

> **SDK tidak boleh menjadi penyebab crash aplikasi host.**
>
> Seluruh entry point publik dan callback internal wajib defensif. Kegagalan internal SDK ditangani secara senyap dan dilaporkan lewat MOB-27 — **tidak pernah dilempar ke aplikasi host**.
>
> Ini bukan sekadar kualitas. SDK ini akan dipasang di aplikasi tim lain; satu crash yang berasal darinya akan menghentikan adopsi secara permanen, dan reputasi itu jauh lebih mahal dipulihkan daripada dijaga.

Konsekuensi praktis:
- Setiap method publik membungkus isinya dengan penanganan error menyeluruh
- Kegagalan I/O disk tidak boleh melempar exception ke pemanggil
- Parsing response server tidak boleh mengasumsikan bentuk payload
- Rollout selalu bertahap: app sendiri dulu sebagai canary, baru ditawarkan ke tim lain

---

## 5. Budget Performa

Dilanggar = tidak boleh rilis. **Diukur otomatis di CI**, bukan diperiksa manual.

| Aspek | Batas |
|---|---|
| Penambahan ukuran app | ≤ 1,5 MB per platform (terkompresi) |
| Overhead cold start | ≤ 30 ms (p95) |
| Main thread | **Nol** operasi I/O blocking; seluruh pekerjaan di background queue/thread |
| CPU | ≤ 2% rata-rata saat penggunaan normal |
| Memori | ≤ 8 MB resident |
| Disk | ≤ 20 MB |
| Baterai | Tanpa background wakeup khusus untuk upload; menumpang siklus hidup app |
| Retensi offline | Minimal 7 hari data tersimpan saat tidak ada koneksi |

---

## 6. Keamanan Sisi Client

### 6.1 Scrubbing — mencegah PII masuk pipeline

Aplikasi yang dimonitor mengalirkan nomor telepon dan data user lain. **Ancaman utamanya bukan pengumpulan yang disengaja, melainkan kebocoran tak sengaja:**

| Jalur kebocoran | Contoh |
|---|---|
| Path URL | `/api/v2/user/628123456789/profile` |
| Query parameter | `?msisdn=0812xxxx&otp=...` |
| Pesan error | `"Gagal mengirim OTP ke 0812xxxxxxx"` |
| Breadcrumb / atribut manual | `logError(e, ["phone": user.phone])` |
| Nama screen | `OTPVerification-0812xxxxxxx` |

| ID | Requirement | Prio |
|---|---|---|
| SEC-01 | **Scrubbing dilakukan sebelum penulisan ke disk.** Membersihkan di server tidak cukup — begitu data tertulis di disk device, permukaan kebocoran sudah terbentuk. | P0 |
| SEC-02 | Header HTTP memakai **allowlist**, bukan blocklist. Default hanya `Content-Type`, `Content-Length`, `Accept`, `User-Agent`. `Authorization`, `Cookie`, dan header kustom tidak pernah tercatat. | P0 |
| SEC-03 | Query parameter di-redaksi; hanya nama parameter disimpan, nilainya diganti `[redacted]`. Allowlist dapat dikonfigurasi per app. | P0 |
| SEC-03b | **Normalisasi path URL:** segmen berupa angka panjang, UUID, atau pola identitas diganti placeholder — `/user/628123456789/profile` → `/user/{id}/profile`. Juga meningkatkan kualitas grouping di backend. | P0 |
| SEC-04 | Request & response body **tidak pernah** ditangkap. Tidak ada opsi mengaktifkannya di v1. | P0 |
| SEC-05 | Redaksi pola diterapkan ke **seluruh string** yang masuk pipeline — termasuk pesan error, `reason` crash, pesan breadcrumb, dan atribut kustom. Pola minimal: nomor telepon Indonesia (`08xx`, `+62xx`), email, string mirip JWT, deret angka ≥ 10 digit. | P0 |
| SEC-05b | Redaksi berjalan sebagai **lapisan terakhir** sebelum penulisan ke disk, sehingga berlaku juga untuk data yang dikirim developer lewat API manual. Asumsinya developer akan lupa — SDK tidak boleh bergantung pada kedisiplinan pemanggilnya. | P0 |
| SEC-06 | **`user_id` bebas diisi app host** — SDK tidak memvalidasi atau menolak isinya (boleh nomor telepon, email, atau teks apa pun). Hashing menjadi `user_ref` dilakukan **backend** di ingestion (BE-21), bukan SDK. Kewajiban SDK: `user_id` mentah hanya menempati slot `user_id` di envelope — **tidak boleh** bocor ke breadcrumb, log debug, atau field lain. | P0 |

> **Perubahan dari desain awal (Opsi B):** versi sebelumnya menolak `user_id` yang menyerupai PII. Sekarang app host boleh mengisi apa pun, karena backend meng-hash-nya menjadi `user_ref` yang opaque sebelum disimpan (`01` §2.1 & BE-21). Postur "tidak menyimpan PII" tetap terjaga — yang berubah hanya *di mana* penyamaran terjadi: di server, bukan di client. Alasan memilih ini: app host bebas memakai identifier apa pun (nomor telepon dari sistem utama, dsb.) tanpa membebani mereka aturan validasi, sementara storage tetap bersih dari identitas langsung.

### 6.2 Data at rest di device

| ID | Requirement | Prio |
|---|---|---|
| SEC-07 | **iOS:** file antrean memakai `FileProtectionType.completeUntilFirstUserAuthentication`, ditandai dikecualikan dari backup. **Android:** internal storage, dikecualikan dari auto-backup. | P0 |
| SEC-08 | Enkripsi antrean at-rest: AES-GCM, kunci di Keychain / Android Keystore | P1 |
| SEC-09 | **Pengecualian eksplisit untuk crash report** — lihat kotak di bawah | P0 |

> ### Trade-off yang disengaja: crash report tidak dienkripsi saat ditulis
>
> Penulisan crash report terjadi di dalam signal handler. Di konteks itu, alokasi memori tidak *async-signal-safe*, sehingga menjalankan kriptografi berisiko membuat proses hang atau crash kedua kali — kehilangan data yang justru sedang coba diselamatkan.
>
> **Solusinya:** crash report ditulis mentah dengan payload seminimal mungkin (tanpa PII sama sekali), lalu dienkripsi saat peluncuran aplikasi berikutnya.
>
> Trade-off ini **didokumentasikan sejak awal** agar tidak muncul sebagai temuan tak terduga saat security review.

### 6.3 Komunikasi & kredensial

| ID | Requirement | Prio |
|---|---|---|
| SEC-10 | TLS 1.2+ untuk seluruh komunikasi SDK ke endpoint ingestion; cleartext dinonaktifkan di level platform (ATS di iOS, network security config di Android) | P0 |
| SEC-11 | Certificate pinning pada endpoint ingestion — **opsional, tidak aktif secara default** (lihat keputusan di bawah). Bila dinyalakan per-app, **wajib** menyertakan pin cadangan dan kill switch via remote config. | P2 |
| SEC-12 | Jika validasi TLS gagal karena sebab apa pun: **fail closed** — data tetap di disk, tidak pernah fallback ke koneksi tanpa proteksi. Berlaku terlepas dari SEC-11 aktif atau tidak. | P0 |

> ### Keputusan: pinning tidak diaktifkan secara default (SEC-11 → P2)
>
> **Konteks.** Ada dua koneksi berbeda yang sering tertukar:
>
> | Koneksi | Client-nya | Yang melakukan pinning |
> |---|---|---|
> | App host → API bisnis | App host | App host. SDK hanya **mengamati** hasilnya (`ssl_pinning_rejected`, MOB-03) |
> | **SDK → endpoint ingestion APM** | **SDK** | SDK — inilah lingkup SEC-11 |
>
> **Alasan diturunkan.** Biaya operasionalnya tidak sebanding dengan ancaman yang ditutup. Rotasi sertifikat server ingestion (rutin, biasanya tahunan) akan menghentikan pengiriman telemetri di **seluruh app terpasang sekaligus**, dan pemulihannya menuntut rilis app baru plus menunggu user memperbarui — berminggu-minggu tanpa visibilitas. Ancaman yang ditutup pinning hanya berlaku bila penyerang sudah mampu menanam CA palsu di device user; pada titik itu perusahaan menghadapi masalah yang jauh lebih besar daripada penyadapan data telemetri.
>
> Nilai data yang ditransmisikan juga rendah secara relatif: `user_id` mentah (langsung di-hash di ingestion, BE-21), path yang sudah dinormalisasi, dan breadcrumb yang sudah di-scrub. Request/response body tidak pernah ditangkap sama sekali (SEC-04).
>
> **Catatan penting.** Proyek ini lahir dari insiden kegagalan pinning yang membuat tim kehilangan visibilitas. Membangun sistem monitoring yang bisa mematikan dirinya sendiri dengan mekanisme yang persis sama adalah risiko yang tidak masuk akal untuk diambil secara default.
>
> **Jalur naik.** Bila suatu tim adopter membutuhkan jaminan lebih kuat (atau muncul tuntutan compliance), pinning dapat dinyalakan sebagai **opsi konfigurasi per-app** — dengan syarat mutlak pin cadangan + kill switch. Itu menjadi keputusan sadar per aplikasi, bukan default yang diam-diam berisiko.
| SEC-13 | Kunci app diperlakukan sebagai **identifier, bukan credential** — kunci yang tertanam di binary dapat diekstrak siapa pun. Konsekuensinya kunci bersifat write-only. | P0 |
| SEC-14 | Kunci dapat dirotasi lewat remote config tanpa rilis app baru | P1 |

### 6.4 Integritas SDK

| ID | Requirement | Prio |
|---|---|---|
| SEC-19 | Rilis dari repository artifact internal, checksum dipublikasikan, dependensi pihak ketiga minimal dan versinya dikunci | P0 |
| SEC-20 | Tidak ada eksekusi kode dinamis; remote config hanya boleh mengubah flag yang telah didefinisikan, tidak pernah perilaku eksekusi | P0 |
| SEC-21 | Dokumen **data inventory** resmi: daftar lengkap data yang dikumpulkan SDK | P0 |
| SEC-22 | **Konsekuensi rilis untuk semua app adopter:** setiap app yang meng-embed SDK wajib memperbarui privacy label di App Store Connect dan formulir Data Safety di Play Console. Tanpa ini, rilis berisiko ditolak. Dokumen SEC-21 menjadi rujukan pengisiannya. | P0 |

---

## 7. Definition of Done per Fase

**Fase 1 (M1) — iOS**
- [ ] Seluruh MOB P0 Fase 1 terpenuhi
- [ ] Scrubbing P0 (SEC-01 s/d SEC-05b) terpasang dan diuji dengan payload berisi nomor telepon
- [ ] `setUser(id)` + fallback generate berjalan (MOB-28); diverifikasi bersama Backend bahwa `user_id` mentah **tidak** tersimpan setelah di-hash jadi `user_ref` (BE-21)
- [ ] Flag `integrity` (emulator/root/dev-mode) terisi benar di device uji nyata (MOB-29..31)
- [ ] Budget performa §5 lolos di CI
- [ ] Data dari 1 app pilot masuk ke backend selama ≥ 2 minggu tanpa regresi crash-free rate
- [ ] Skenario diuji: SSL gagal, offline penuh, force quit saat upload, disk penuh

**Fase 2 (M2–M3)**
- [ ] Android mengirim payload yang identik dengan iOS untuk kasus uji yang sama
- [ ] Crash tersimbolikasi otomatis di kedua platform
- [ ] Kill switch terbukti berfungsi di production

**Fase 3 (M5)**
- [ ] Sample app + dokumen integrasi selesai; diuji dengan satu tim adopter nyata
- [ ] Data inventory (SEC-21) diserahkan ke semua tim adopter