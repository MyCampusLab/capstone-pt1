# PRODUCT REQUIREMENT DOCUMENT (PRD v2.0)
## SMARTBARBER ECOSYSTEM: PLATFORM MANAJEMEN ANTREAN & KASIR MULTI-TENANT
### IMPLEMENTASI RISET TERAPAN & DIGITALISASI UMKM VOKASI (UNIVERSITAS HARKAT NEGERI)

---

## 1. Problem Statement
Tiga unit usaha barbershop di wilayah Kota dan Kabupaten Tegal (Febrian Barbershop Mejasem, RR Barber Studio, dan Stupid Culture Barbershop) menghadapi kendala operasional harian yang serupa:
1. **Kehilangan Pelanggan Langsung (*Walk-in Drop-off*):** Rata-rata 15–25% calon pelanggan langsung membatalkan niat cukur saat melihat ruang tunggu penuh karena tidak adanya transparansi waktu antrean.
2. **Bentrok Jadwal Reservasi:** Pemesanan jadwal secara manual lewat chat WhatsApp sering bentrok dengan pelanggan fisik yang sudah terlanjur duduk di ruang tunggu.
3. **Ketimpangan Beban Kerja Kapster (*Workload Imbalance*):** Antrean manual memicu penumpukan beban fisik pada satu kapster favorit di jam sibuk, sementara kapster lainnya mengalami waktu menganggur (*idle time*).
4. **Hambatan Biaya Software POS:** Software POS ritel umum membebankan biaya lisensi bulanan yang mahal tanpa menyediakan logika penjadwalan antrean dinamis multi-kapster.

Dampak jika tidak diselesaikan: UMKM kehilangan potensi pendapatan harian dan kapster mengalami kelelahan kerja (*burnout*).

---

## 2. Goals & Non-Goals

### A. Goals (Sasaran Terukur)
1. **Akurasi Estimasi Waktu Tunggu:** Menghasilkan prediksi durasi potong rambut dinamis menggunakan logika Fuzzy Sugeno Orde-Nol dengan akurasi $\text{MAPE} < 15\%$ dan $\text{MAE} < 4.0\text{ menit}$.
2. **Pemerataan Beban Kerja Kapster:** Mengurangi variansi total menit kerja antar-kapster aktif hingga minimal 30% menggunakan heuristik Smart Dispatch (*Earliest Finish Time*).
3. **Eliminasi Bentrok Antrean:** Mencapai zero-booking collision melalui model antrean hibrida terverifikasi QR Check-in meja kasir.
4. **Kesiapan Skalabilitas Multi-Tenant:** Mengisolasi data katalog, kapster, dan transaksi 3 mitra barbershop dalam satu basis data relasional PostgreSQL Twelve-Factor terpadu.

### B. Non-Goals (Batasan Ruang Lingkup)
1. **Tidak Membangun Payment Gateway Perbankan Sendiri:** Sistem menggunakan metode transfer manual dengan verifikasi bukti unggah gambar presigned S3/MinIO dan QRIS statis ruko.
2. **Tidak Menggunakan Modul AI Generatif / Chatbot:** Modul NLP chatbot dan computer vision dihilangkan total untuk menjaga performa aplikasi tetap deterministik, ringan, dan fokus pada komputasi antrean.
3. **Tidak Menjual Produk Ritel Fisik:** Ruang lingkup v2.0 terfokus 100% pada pemesanan jasa potong rambut dan manajemen antrean kapster.

---

## 3. Target Personas

| Persona | Peran Utama | Kebutuhan Utama | Titik Masalah (*Pain Point*) |
|---|---|---|---|
| **Pelanggan (*Customer*)** | Pengguna aplikasi mobile / web booking. | Mengetahui estimasi pasti giliran potong rambut, memantau posisi antrean secara live. | Malas menunggu di ruko tanpa kepastian waktu potong. |
| **Kapster (*Barberman*)** | Penyedia jasa potong rambut fisik. | Beban kerja harian yang seimbang, kepastian waktu istirahat bergantian. | Kelelahan fisik saat jam sibuk karena pelanggan menumpuk di kursinya. |
| **Kasir / Pemilik (*Tenant Admin*)** | Pengelola operasional harian cabang. | Panel antrean cepat (two-tap), pencatatan walk-in instan, rekapitulasi jumlah potong kapster. | Repot mencatat manual di buku nota saat ruko ramai. |
| **Super Admin (Platform UHN)** | Pengelola ekosistem multi-tenant. | Onboarding tenant baru, pemantauan metrik MAE/MAPE lintas-cabang untuk laporan skripsi. | Kesulitan mengumpulkan log durasi potong riil secara serentak. |

---

## 4. System Requirements

### Must-Have (P0 - Inti Rilis v2.0)
- **P0-1 (Multi-Tenant Data Isolation):** Isolasi skema data `tenants`, `barbers`, `services`, dan `queue_reservations` menggunakan relasi `tenant_id` pada PostgreSQL.
- **P0-2 (Fuzzy Sugeno Duration Engine):** Mesin inferensi 9 aturan Sugeno Orde-Nol di server backend dengan input tingkat kerumitan ($X_1$) dan indeks kecepatan kapster ($X_2$).
- **P0-3 (Smart Dispatch Allocation):** Heuristik alokasi kapster otomatis berbasis backlog durasi menit terendah dan jeda transisi (*buffer time*) 5 menit saat pelanggan memilih "Kapster Bebas".
- **P0-4 (Live Queue State Machine):** Status tiket antrean berjenjang (`waiting` $\to$ `checked_in` $\to$ `in_service` $\to$ `completed` / `cancelled`) yang disinkronkan real-time via WebSocket Socket.IO.
- **P0-5 (Presigned S3 Image Storage):** Pengunggahan berkas bukti transfer langsung ke Object Storage S3/MinIO dengan penghapusan total penyimpanan string Base64 di database.
- **P0-6 (Cashier Panel Fast Actions):** Antarmuka kasir untuk pendaftaran pelanggan walk-in instan (< 15 detik) dan tombol panggil/selesai satu ketukan.

### Nice-to-Have (P1 - Fast Follow-up)
- **P1-1 (Grace Period Auto-Hold):** Otomatis menurunkan status pelanggan daring yang telat hadir 10 menit dari jadwal ke status `on_hold` agar antrean fisik tidak tertahan.
- **P1-2 (Export CSV Evaluasi Skripsi):** Tombol ekspor tabel log perbandingan durasi prediksi vs durasi aktual langsung ke format CSV untuk analisis spreadsheet Bab 4 Skripsi.

---

## 5. Technical Architecture (Twelve-Factor Compliance)

```text
               +-------------------------------------------+
               |        MOBILE & WEB PRESENTATION          |
               |  - Flutter Customer App (Clean Arch)      |
               |  - Responsive Cashier Web Console         |
               +--------------------+----------------------+
                                    | REST / WebSocket
                                    v
+-------------------------------------------------------------------------+
|                  BACKEND CORE ENGINE (TWELVE-FACTOR)                    |
|  [Factor I: Git]   [Factor III: Zod Env]   [Factor VI: Stateless Node]  |
|  [Factor VII: Port Binding 4000]           [Factor XI: Pino JSON Logs]  |
|                                                                         |
|  +----------------------+  +---------------------+  +-----------------+ |
|  | Multi-Tenant Router  |  | Fuzzy Sugeno Engine |  | Smart Dispatch  | |
|  | - Tenants Catalog    |  | - 9 Sugeno Rules    |  | - Earliest      | |
|  | - Atomic Booking     |  | - Weighted Average  |  |   Finish Time   | |
|  +----------+-----------+  +----------+----------+  +--------+--------+ |
|             |                         |                      |          |
|             +-------------------------+----------------------+          |
+-----------------------------------+-------------------------------------+
                                    |
            +-----------------------+-----------------------+
            | Factor IV: Backing Services (Attached via Env)|
            v                                               v
+-----------------------+                       +-----------------------+
|  PostgreSQL 16 DB     |                       |  MinIO / S3 Storage   |
|  - ACID Atomic Locks  |                       |  - Proof Images       |
|  - 3 Mitra Tenants    |                       |  - Pre-signed Uploads |
+-----------------------+                       +-----------------------+
```

---

## 6. Mathematical Formulation (Core Algorithms)

### A. Estimasi Durasi (Fuzzy Sugeno Orde-Nol)
- **Fungsi Keanggotaan $X_1$ (Kerumitan Layanan: 1.0 - 10.0):**
  - $\mu_{\text{Ringan}}(x)$: Bahu kiri $[1.0, 4.5]$
  - $\mu_{\text{Sedang}}(x)$: Segitiga $[2.5, 7.5]$
  - $\mu_{\text{Tinggi}}(x)$: Bahu kanan $[5.5, 10.0]$
- **Fungsi Keanggotaan $X_2$ (Kecepatan Kapster: 15 - 45 Menit):**
  - $\mu_{\text{Cepat}}(y)$: Bahu kiri $[15, 27]$
  - $\mu_{\text{Standar}}(y)$: Segitiga $[22, 38]$
  - $\mu_{\text{Teliti}}(y)$: Bahu kanan $[33, 45]$
- **Defuzifikasi Rata-Rata Terbobot (*Weighted Average*):**
  $$Z^* = \frac{\sum_{i=1}^{9} \alpha_i \cdot z_i}{\sum_{i=1}^{9} \alpha_i}, \quad \alpha_i = \min(\mu_{X_1, i}, \mu_{X_2, i})$$

### B. Smart Dispatch Heuristic (Workload Allocation)
$$\text{Backlog}(k) = \sum_{j \in Q_k} \max(0, \text{EstFinish}_j - \text{ReferenceTime}) + \text{BufferMinutes}$$
Kapster terpilih $k^* = \arg\min_{k \in K_{\text{active}}} \text{Backlog}(k)$, dengan pemecah seri (*tie-breaker*) nomor kursi terendah.

---

## 7. Success Metrics & Validation Rubric

| Metrik Evaluasi | Target Kriteria | Metode Pengukuran |
|---|---|---|
| **Mean Absolute Error (MAE)** | $< 4.0\text{ menit}$ | $\frac{1}{n}\sum |Actual - Predicted|$ |
| **Mean Absolute Pct Error (MAPE)** | $< 15.0\%$ | $\frac{1}{n}\sum |\frac{Actual - Predicted}{Actual}| \times 100\%$ |
| **Workload Variance Reduction** | $\ge 30\%$ | Perbandingan variansi standar deviasi antrean manual vs Smart Dispatch |
| **API Response Latency** | $< 50\text{ ms}$ | Uji benchmarking endpoint `/api/queue/book` pada beban konkurensi |
| **Database Concurrency Safety** | Zero collision | 10+ simulasi booking serentak tanpa duplikasi nomor antrean |
