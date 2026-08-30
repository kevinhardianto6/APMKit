# 00 — Overview

**PRD APM Kit** · Konteks bersama untuk semua tim

> Dokumen ini menjelaskan **kenapa** proyek ini ada dan **apa** yang dibangun secara garis besar.
> Detail teknis ada di dokumen per tim. Kontrak data & API ada di `01-Kontrak-Data-API.md`.

---

## 1. Ringkasan

APM Kit adalah SDK monitoring yang di-embed ke aplikasi mobile internal, didukung backend on-premise untuk ingestion & storage, dan website backoffice untuk analisis. Tujuannya memberi tim engineering visibilitas atas apa yang sebenarnya terjadi di aplikasi saat berjalan di device user — crash, kegagalan network, error SDK pihak ketiga, dan degradasi performa.

**Prinsip desain utama: *write local first, sync later*.** Setiap event ditulis ke penyimpanan lokal device terlebih dahulu tanpa menyentuh network, lalu dikirim ke server saat kondisi memungkinkan.

Ini yang membedakan APM Kit dari tool yang mengirim log secara real-time: saat network bermasalah — justru momen paling penting untuk diobservasi — datanya tetap terekam.

---

## 2. Latar Belakang & Masalah

Insiden production yang saat ini tidak bisa didiagnosa secara memadai:

| Masalah | Kondisi saat ini | Dampak |
|---|---|---|
| **Crash di device user** | Hanya diketahui dari keluhan user; tidak ada stack trace maupun konteks | Sulit direproduksi, perbaikan berbasis tebakan |
| **Kegagalan fetch Firebase** | Tidak tercatat di mana pun | Tidak terdeteksi sampai user komplain |
| **SSL pinning handshake gagal** | Koneksi mati total; tool logging berbasis network kehilangan datanya sendiri | Root cause tidak diketahui, waktu investigasi panjang |
| **Regresi performa antar-rilis** | Tidak terukur | Degradasi baru diketahui setelah user mengeluh |

**Akar masalah:** tool monitoring konvensional bergantung pada network untuk mengirim log. Ketika network gagal, observabilitas ikut hilang.

**Kenapa build sendiri, bukan pakai vendor:** kendali penuh atas data (tidak keluar ke pihak ketiga), kemampuan kustomisasi untuk kebutuhan spesifik seperti deteksi pinning failure yang granular, tidak ada risiko layanan dihentikan seperti App Center, dan biaya tidak naik seiring pertumbuhan volume event atau jumlah seat.

---

## 3. Tujuan & Non-Tujuan

### Tujuan

| ID | Tujuan |
|---|---|
| G1 | Setiap crash di production tercatat lengkap dengan stack trace tersimbolikasi dan jejak aksi user sebelumnya |
| G2 | Semua kegagalan network — termasuk yang terjadi saat koneksi mati — terekam dan terkategorisasi otomatis |
| G3 | Tim bisa menentukan prioritas perbaikan berdasarkan data kuantitatif (frekuensi, jumlah user terdampak, versi terdampak) |
| G4 | SDK bisa diadopsi tim lain di perusahaan dengan effort integrasi minimal |
| G5 | Data monitoring sepenuhnya berada di infrastruktur perusahaan |
| G6 | Sinyal environment device (emulator/root/dev-mode) terekam agar sesi non-real bisa disaring — metrik mencerminkan user asli |

### Non-Tujuan (untuk v1)

- Bukan pengganti tool observability backend (server tracing, log aggregation server-side)
- Bukan analitik produk (funnel, retention, A/B testing)
- Tidak melakukan session replay atau perekaman layar
- Tidak melakukan Real User Monitoring untuk web
- Tidak menyediakan distribusi SDK ke pihak eksternal di luar perusahaan

> Non-tujuan tidak dinegosiasi ulang sebelum M5. Ini pengendali utama beban maintenance.

---

## 4. Metrik Keberhasilan

| Metrik | Target v1 | Cara ukur |
|---|---|---|
| Adopsi | ≥ 3 app internal terintegrasi dalam 2 kuartal | Jumlah app_id aktif |
| Kelengkapan data | ≥ 95% event yang tercatat di device sampai ke backend dalam 24 jam | Rasio event terkirim vs tercatat (dilaporkan SDK) |
| Waktu diagnosa | Median waktu dari laporan bug ke identifikasi root cause turun ≥ 50% | Survei tim + sampling tiket |
| Stabilitas SDK | Kontribusi SDK terhadap crash aplikasi host = 0 | Crash-free rate app sebelum vs sesudah integrasi |
| Overhead | Memenuhi seluruh budget performa (`02-Mobile-SDK.md` §5) | Benchmark otomatis di CI |

---

## 5. Pengguna

| Persona | Kebutuhan utama | Permukaan yang dipakai |
|---|---|---|
| **Mobile engineer** | Melihat detail crash & error di app-nya, mereproduksi masalah | Website: issue detail, breadcrumb timeline |
| **Backend engineer** | Melihat endpoint mana yang error/lambat dari sisi client | Website: network explorer |
| **QA** | Memverifikasi rilis tidak membawa regresi | Website: release comparison |
| **Engineering lead** | Menentukan prioritas berdasarkan dampak | Website: overview dashboard, alerting |
| **Tim adopter (tim lain)** | Integrasi cepat tanpa bantuan intensif | SDK: dokumentasi, sample app |

---

## 6. Arsitektur Ringkas

```
┌─────────────────────────────┐
│  MOBILE APP (iOS/Android)   │   → 02-Mobile-SDK.md
│  Capture → Scrub → Disk     │
│  Queue → Sync Engine        │
└──────────────┬──────────────┘
               │ HTTPS (TLS 1.2+)
               ▼
┌─────────────────────────────┐
│  BACKEND (on-premise)       │   → 03-Backend.md
│  Ingestion → Queue →        │
│  Worker (fingerprint,       │
│  symbolication) → Storage   │
└──────────────┬──────────────┘
               │ Read API
               ▼
┌─────────────────────────────┐
│  WEBSITE (Backoffice)       │   → 04-Frontend-Website.md
│  Dashboard · Issues ·       │
│  Network · Alerting         │
└─────────────────────────────┘
```

**Keputusan arsitektur yang mengikat semua tim:**

1. Ingestion hanya menerima & mengantrikan. Seluruh pemrosesan berat dilakukan worker asinkron. Ini menjaga latensi ingestion rendah dan mencegah lonjakan traffic device mengganggu ketersediaan.
2. Pengiriman bersifat **at-least-once** — event bisa sampai lebih dari sekali, tidak pernah hilang. Karenanya deduplikasi di backend bersifat wajib.
3. Dashboard berorientasi **Issue**, bukan event mentah.

---

## 7. Fase & Pembagian Kerja

| Fase | Mobile | Backend | Frontend |
|---|---|---|---|
| **Fase 1** | Network observability, disk queue, sync, error API, breadcrumbs, `setUser`, sinyal integrity (iOS) | Ingestion API minimal, registry app, storage, **hash `user_id`→`user_ref`** | — |
| **Fase 2** | Paritas Android, crash reporting, remote config | Fingerprinting, symbolication, config endpoint | — |
| **Fase 3** | Sampling, dokumentasi & sample app | Read API, agregasi, resolve+lookup, filter integrity, alerting, RBAC | Seluruh backoffice (termasuk User Lookup & filter integrity) |

Selama Fase 1–2, visualisasi sementara boleh memakai tool open-source agar tim tidak menunggu Fase 3 untuk mendapat manfaat.

---

## 8. Milestone

| Milestone | Isi | Keluaran |
|---|---|---|
| **M0** | Review & persetujuan PRD, finalisasi kontrak schema, spike teknis, sizing kapasitas | Schema terkunci, spesifikasi server ditentukan, pengadaan dimulai |
| **M1** | SDK iOS Fase 1 + ingestion API minimal | 1 app pilot di production |
| **M2** | Paritas SDK Android | Kedua platform mengirim data dengan schema identik |
| **M3** | Crash reporting + symbolication pipeline | Crash tersimbolikasi otomatis |
| **M4** | Backend production-grade + website v1 | Dashboard bisa dipakai tim |
| **M5** | Hardening keamanan, dokumentasi, onboarding tim lain | ≥ 3 app terintegrasi secara self-serve |

**Kriteria kelulusan tiap milestone:** seluruh requirement P0 pada fase tersebut terpenuhi, budget performa tidak dilanggar, dan tidak ada regresi crash-free rate pada app pilot.

---

## 9. Profil Data & Postur Privasi

Aplikasi yang dimonitor tidak menangani kategori data sangat sensitif (finansial, kesehatan), **namun nomor telepon dan data user lain mengalir di dalamnya**. Di bawah UU No. 27 Tahun 2022 tentang Pelindungan Data Pribadi, nomor telepon termasuk **data pribadi bersifat umum** — bukan kategori spesifik, tetapi tetap diatur.

**Keputusan desain (Opsi B): identifier bebas diisi app host, tapi storage tidak pernah memuat identitas langsung.** App host boleh mengisi `user_id` dengan apa pun (nomor telepon, email, user ID internal, atau teks lain). Di ingestion, backend meng-hash-nya menjadi `user_ref` opaque (`HMAC-SHA256` dengan key yang hanya ada di server); **hanya hash yang disimpan**, nilai mentah dibuang (BE-21). Untuk mencari "user mana yang kena", support memasukkan nomor telepon/email → di-resolve menjadi `user_ref` di server (hash dengan cara yang sama) → ketemu (`01` §10, BE-23). Nomornya sendiri tidak pernah disimpan.

> **Alasan:** database APM akan dibaca banyak engineer dari banyak tim — kombinasi terburuk untuk menyimpan PII (banyak pembaca, tujuan luas, retensi panjang). Dengan menyimpan hanya hash opaque, blast radius kebocoran jauh lebih kecil dan alur support tetap penuh. App host juga tidak dibebani aturan validasi identifier — mereka pakai apa pun yang natural, penyamaran terjadi di server. **Trade-off jujur:** nilai mentah tetap *melewati* endpoint ingestion (via TLS) sebelum di-hash-dan-dibuang — klaim yang benar "tidak disimpan", bukan "tidak pernah dikirim". Jika suatu saat diputuskan menyimpan nilai mentah, syarat SEC-P1–P7 (`03` §7) wajib dipenuhi lebih dulu.

**Ancaman utamanya bukan pengumpulan yang disengaja, melainkan kebocoran tak sengaja** — nomor telepon menyelinap masuk lewat path URL, pesan error, atau breadcrumb yang ditulis developer. Penanganannya ada di `02-Mobile-SDK.md` §6 (scrubbing berlapis) dan `03-Backend.md` §7 (audit kebocoran berkala).

---

## 10. Risiko

| Risiko | Dampak | Mitigasi | Pemilik |
|---|---|---|---|
| Bug SDK menyebabkan crash di app tim lain | Sangat tinggi — merusak kepercayaan, menghentikan adopsi | Entry point defensif, kill switch (MOB-21), rollout bertahap, canary di app sendiri | Mobile |
| Nomor telepon bocor ke storage lewat jalur tak terduga (URL/error/breadcrumb **atau** `user_id`) | Tinggi — APM berubah jadi basis data PII tanpa disengaja | Scrubbing berlapis (SEC-03b, SEC-05) · `user_id` di-hash di ingestion (BE-21) · `server_key` server-side (SEC-28) · audit kebocoran (SEC-24) | Mobile + Backend |
| Rotasi sertifikat mematikan telemetri seluruh app | Tinggi | Dihindari secara desain: pinning **tidak aktif secara default** (SEC-11 → P2). Bila suatu app menyalakannya, wajib pin cadangan + kill switch | Mobile |
| Symbol tidak terupload → crash report tak terbaca | Tinggi | CI gagal jika upload gagal, peringatan eksplisit di dashboard (FE-17) | Mobile + Backend |
| Disk penuh di server on-premise → data hilang | Tinggi | Alert di 70% kapasitas (OPS-05), TTL retensi, sampling, runbook | Backend |
| Endpoint ingestion terbuka ke internet jadi sasaran abuse | Sedang | WAF + rate limit di DMZ (OPS-04), kunci write-only, quota per install | Backend |
| Adopsi tim lain rendah karena integrasi merepotkan | Sedang | Sample app + dokumentasi, target integrasi < 30 menit (MOB-25) | Mobile |
| Divergensi perilaku iOS vs Android | Sedang | Schema & enum sebagai kontrak bersama, tes lintas platform | Mobile |
| Tidak ada pemilik operasional backend on-premise | Sedang | Ditetapkan sebagai keputusan wajib sebelum M4 | Lead |
| Beban maintenance melebihi kapasitas tim | Sedang | Scope v1 dibatasi ketat; non-tujuan §3 tidak dibuka sebelum M5 | Lead |

---

## 11. Keputusan Terbuka

**Sudah diputuskan:** hosting on-premise · identifier bebas diisi app host tapi di-hash jadi `user_ref` opaque di ingestion, storage tidak simpan nilai mentah (Opsi B) · sinyal integrity (emulator/root/dev-mode) via heuristik di v1 · SDK internal saja.

| # | Keputusan | Implikasi | Sebelum |
|---|---|---|---|
| 1 | Engine storage time-series | Kemampuan query & biaya; harus wajar dioperasikan tim kecil di on-premise | M4 |
| 2 | Spesifikasi server & kapasitas awal | Menentukan pengadaan hardware — perlu dimulai awal karena ada lead time | M3 |
| 3 | Pemilik operasional backend | On-premise berarti uptime jadi tanggung jawab tim sendiri | M4 |
| 4 | Library crash reporting yang sudah ada vs tulis sendiri | Tulis sendiri berisiko tinggi; library matang hemat waktu tapi nambah dependensi | M3 |
| 5 | Strategi sampling default | Kelengkapan data vs kapasitas disk | M4 |
| 6 | Kanal alerting | Integrasi backend | M4 |
| 7 | Periode retensi final | Biaya storage vs kedalaman analisis historis | M4 |
| 8 | Konvensi isi `user_id` lintas tim adopter | Agar `user_ref` konsisten dengan sistem utama tiap tim, sehingga resolve by nomor HP/email cocok | M1 |
| 9 | Upgrade sinyal integrity ke attestation (Play Integrity / App Attest) | Hanya bila device-integrity mau dijadikan security gate, bukan sekadar observability — v1 pakai heuristik | pasca-v1 |

---

## 12. Glosarium

| Istilah | Penjelasan |
|---|---|
| **Breadcrumb** | Catatan kronologis aksi kecil sebelum terjadi error — seperti kotak hitam pesawat. Crash report menjelaskan *di mana* aplikasi berhenti; breadcrumb menjelaskan *apa yang terjadi sebelumnya*. |
| **Symbolication** | Menerjemahkan alamat memori pada stack trace menjadi nama fungsi, file, dan nomor baris, memakai dSYM (iOS) atau mapping file (Android). |
| **Issue** | Sekumpulan event yang dianggap satu masalah yang sama berdasarkan fingerprint. |
| **Fingerprint** | Hash penciri yang menentukan pengelompokan event menjadi Issue. |
| **Envelope** | Pembungkus satu batch event yang memuat konteks statis (app, device, sesi). |
| **At-least-once delivery** | Jaminan pengiriman: event mungkin terkirim lebih dari sekali, tidak pernah hilang. Karenanya backend wajib deduplikasi. |
| **Fail closed** | Saat terjadi kegagalan keamanan, sistem menolak melanjutkan alih-alih mencari jalur alternatif yang kurang aman. |
| **Kill switch** | Mekanisme mematikan SDK dari jarak jauh tanpa perlu merilis versi app baru. |
| **DMZ** | Zona jaringan perantara yang terekspos ke internet, terpisah dari jaringan internal. |
| **Pseudonymous ID** | Pengenal yang merujuk ke seorang user tanpa memuat identitas langsungnya. |
| **`user_id`** | Identifier mentah yang di-set app host (boleh nomor telepon/email/teks) atau di-generate SDK. Ada di envelope, transit lewat TLS, **tidak pernah disimpan mentah**. |
| **`user_ref`** | Hasil `HMAC-SHA256(server_key, user_id)` yang dihitung backend. **Hanya nilai ini yang disimpan** & dipakai downstream. Opaque, tidak bisa dibalik tanpa `server_key`. |
| **HMAC / pepper** | Hash berkunci; `server_key` (pepper) yang rahasia dan hanya ada di server membuat hash `user_ref` tahan brute-force meski input-nya low-entropy seperti nomor telepon. |
| **Sinyal integrity** | Properti environment device (emulator, root/jailbreak, developer mode) yang di-snapshot per sesi. Heuristik, bukan PII; dipakai untuk menyaring/segmentasi. |