# 💈 SMARTBARBER ECOSYSTEM (v2.0)
[![Mobile](https://img.shields.io/badge/Flutter-Mobile_Only-blue?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![Backend](https://img.shields.io/badge/Node.js-Twelve_Factor-green?style=for-the-badge&logo=nodedotjs)](https://12factor.net)
[![Database](https://img.shields.io/badge/PostgreSQL-Multi_Tenant-blue?style=for-the-badge&logo=postgresql)](https://www.postgresql.org)
[![Institution](https://img.shields.io/badge/UHN-Sekolah_Vokasi-red?style=for-the-badge)](https://harkatnegeri.ac.id)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

> **Platform Manajemen Antrean dan Kasir Multi-Tenant Berbasis Logika Fuzzy Sugeno dan Smart Dispatch Heuristic.**  
> Proyek Riset Terapan & Digitalisasi UMKM Vokasi — Sarjana Terapan Teknik Informatika, Sekolah Vokasi, Universitas Harkat Negeri (2026).

---

## 🌟 Visi & Problem Statement
Mendigitalisasi ekosistem antrean dan operasional kasir barbershop mitra di wilayah Kota & Kabupaten Tegal guna menyelesaikan 4 masalah inti:
1. **Eliminasi Kehilangan Pelanggan (*Walk-in Drop-off*):** Transparansi nomor tiket dan estimasi menit tunggu real-time di smartphone pelanggan.
2. **Pencegahan Bentrok Antrean:** Penyelarasan antrean fisik dan reservasi daring melalui verifikasi QR Check-in di meja kasir.
3. **Pemerataan Beban Kerja Kapster (*Workload Balancing*):** Heuristik Smart Dispatch mengalokasikan antrean otomatis ke kapster yang paling cepat selesai (*Earliest Finish Time*).
4. **Isolasi Multi-Mitra Skalabel:** Satu platform terpadu melayani 3 barbershop kemitraan nyata dengan katalog harga dan kapster terisolasi.

---

## 🏬 Jaringan 3 Barbershop Mitra Resmi (Pilot Batch 1)
1. **Febrian Barbershop** (Mejasem Barat, Kec. Kramat, Kab. Tegal — 4 Kursi, 3 Kapster: Ferdi, Febri, Hakim).
2. **RR Barber Studio** (Tegal, Jawa Tengah — 3 Kursi, 2 Kapster: Kapster 1, Kapster 2).
3. **Stupid Culture Barbershop** (Jl. Kapten Ismail No. 20, Kota Tegal — 3 Kursi, 3 Kapster: Bagas, Reno, Danang).

---

## 📐 Komputasi Cerdas (Inti Kontribusi Skripsi)
- **Fuzzy Sugeno Orde-Nol:** Prediksi durasi pengerjaan potong rambut dinamis non-linear berbasis tingkat kerumitan menu layanan ($X_1 \in [1.0, 10.0]$) dan indeks kecepatan kapster ($X_2 \in [15, 45]\text{ menit}$).  
  $$\text{Target Evaluasi: } \text{MAE} < 4.0\text{ Menit}, \ \text{MAPE} < 15.0\% \quad (\text{Teruji: MAE } 2.80\text{m}, \ \text{MAPE } 9.29\%)$$
- **Smart Dispatch Heuristic:** Alokasi tugas dinamis berbasis backlog waktu riil:  
  $$\text{Backlog}(k) = \sum_{j \in Q_k} \max(0, \text{EstFinish}_j - \text{ReferenceTime}) + \text{BufferMinutes}$$

---

## 🛠️ Arsitektur Sistem (Twelve-Factor SaaS)
- **Mobile Client:** Flutter 3.x murni Android & iOS (Clean Architecture: Presentation $\to$ Domain $\to$ Repository Pattern).
- **Backend API Core (`backend/`):** Node.js 20+ (TypeScript) / Bun, Express REST API + Socket.IO live broadcasting pada port 4000.
- **Relational Database:** PostgreSQL 16 Alpine via Docker Compose (`tenants`, `barbers`, `services`, `queue_reservations`, `queue_logs`).
- **Object Storage:** S3-Compatible Storage (MinIO / Cloudflare R2) dengan pre-signed upload URL untuk bukti transfer (zero Base64 di database).
- **Tooling & Ingress:** Makefile automasi dan Cloudflare Tunnel (`make tunnel`) untuk akses internet publik gratis $0 tanpa sewa VPS.

---

## 🚀 Perintah Operasional Cepat (Root Makefile)

```bash
# 1. Jalankan database PostgreSQL via Docker
make db-up

# 2. Eksekusi migrasi skema dan injeksi seed 3 barbershop mitra
make db-migrate
make db-seed

# 3. Jalankan seluruh pengujian unit & integrasi backend (16 tests pass)
make test

# 4. Jalankan backend server dalam watch mode (port 4000)
make dev

# 5. Buka tunnel HTTPS publik gratis untuk pengujian HP di ruko mitra
make tunnel
```

---

## 📁 Struktur Repositori

```text
capstone-pt1/
├── Makefile                       # Automasi perintah proyek
├── .editorconfig & .gitignore     # Standarisasi format & proteksi secrets
├── backend/                       # Twelve-Factor Backend API Core
│   ├── src/
│   │   ├── algorithms/            # Fuzzy Sugeno & Smart Dispatch (TypeScript)
│   │   ├── config/env.ts          # Validasi Zod environment fail-fast
│   │   ├── database/              # PostgreSQL schema, pool, migrate, seed
│   │   ├── routes/                # Domain router: queue, tenant, media
│   │   ├── tests/                 # Suite unit test, konkurensi, MAE/MAPE
│   │   └── server.ts              # Stateless server & Socket.IO (<70 baris)
│   ├── docker-compose.yml         # PostgreSQL 16 & MinIO S3
│   └── package.json
├── lib/                           # Flutter Mobile Client (Clean Architecture)
│   ├── services/                  # HttpApiClient, HttpQueueRepository
│   ├── screens/                   # Customer (Home, Antrean, Profile), Admin
│   └── models/                    # Data transfer objects & contracts
└── docs/                          # PRD v2.0 & Spesifikasi Teknis
```

---

## 👨‍💻 Peneliti & Pengembang
**M. Irsyad Fachryanto** (NIM: 23090111)  
*Program Studi Sarjana Terapan Teknik Informatika, Sekolah Vokasi, Universitas Harkat Negeri*  
- Portofolio: [irsyad-architect.surge.sh](https://irsyad-architect.surge.sh)  
- LinkedIn: [muhammadirsyadf](https://www.linkedin.com/in/muhammadirsyadf/)
