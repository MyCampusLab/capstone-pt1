# DESIGN SYSTEM SPECIFICATION (DESIGN.md)
## SMARTBARBER ECOSYSTEM (v2.0)
### PANDUAN STANDAR DESAIN ANTARMUKA & DESIGN TOKENS (UNIVERSITAS HARKAT NEGERI)

---

## 1. Filosofi Desain (Warm Editorial Dark Theme)
Sistem antarmuka SmartBarber dirancang dengan estetika **Dark Modern Barbershop** yang mencerminkan nuansa ruko barbershop pria modern di Tegal (seperti Febrian, RR Studio, dan Stupid Culture).

### Prinsip Utama:
1. **Bukan Frankenstein UI:** Dilarang menempelkan komponen animasi berat (`framer-motion`), shader WebGL, atau efek visual yang tidak relevan yang memperlambat performa HP mobile budget.
2. **Kontras Aksesibel (WCAG 2.1 AA):** Setiap teks wajib memiliki rasio kontras minimal **4.5:1** terhadap latar belakang hitam/gelap.
3. **Ergonomi Sentuh Nyata:** Seluruh tombol aksi memiliki tinggi minimal 44–48 dp agar nyaman ditekan oleh jari kasir maupun pelanggan saat berjalan.

---

## 2. Palet Warna & Rasio Kontras (Design Tokens)

Sumber kebenaran tunggal (*Single Source of Truth*) diimplementasikan pada `lib/config/app_colors.dart`:

| Token Name | Nilai Hex | Penggunaan Antarmuka | Rasio Kontras thd Background | Status WCAG 2.1 AA |
|---|---|---|---|---|
| `AppColors.primary` | `#C3A47B` | Tombol utama, lencana tiket emas, highlight aktif | **8.7:1** | **Lolos (AAA)** |
| `AppColors.primaryLight` | `#D6BC97` | Border kartu antrean aktif, hover state | **11.2:1** | **Lolos (AAA)** |
| `AppColors.background` | `#0C0A09` | Latar belakang utama aplikasi (True Stone Black) | - | Latar Dasar |
| `AppColors.surface` | `#1C1917` | Latar belakang kartu barbershop & card kontainer | - | Latar Kartu |
| `AppColors.surfaceElevated` | `#292524` | Latar modal dialog, bottom sheet, chip filter | - | Latar Modal |
| `AppColors.border` | `#44403C` | Garis tepi (*divider*), border kartu yang tidak aktif | - | Batas Visual |
| `AppColors.textPrimary` | `#FAFAF9` | Judul layar, nama barbershop, teks tombol utama | **18.5:1** | **Lolos (AAA)** |
| `AppColors.textSecondary` | `#E7E5E4` | Teks subjudul, deskripsi layanan, jam buka | **13.2:1** | **Lolos (AAA)** |
| `AppColors.textMuted` | `#9E9E9E` | Placeholder / hint teks pencarian, label sekunder | **6.1:1** | **Lolos (AA)** |
| `AppColors.success` | `#10B981` | Status antrean 'Dilayani' / 'Selesai' | **7.5:1** | **Lolos (AA)** |
| `AppColors.warning` | `#F59E0B` | Status 'Menunggu Giliran' (Waiting) | **6.8:1** | **Lolos (AA)** |
| `AppColors.danger` | `#EF4444` | Tombol pembatalan antrean, peringatan error | **5.4:1** | **Lolos (AA)** |

---

## 3. Skala Tipografi (Typography Scale)

| Tingkatan Teks | Ukuran (Size) | Ketebalan (Weight) | Jarak Baris (*Line Height*) | Penggunaan |
|---|---|---|---|---|
| **Display Header** | 24–28 sp | Bold (w800 / w900) | 1.1 | Judul utama layar (*App Title*), nomor tiket emas |
| **Section Title** | 18–20 sp | Bold (w700) | 1.2 | Nama barbershop pada card, judul langkah booking |
| **Card Title** | 15–16 sp | Bold (w600 / w700) | 1.25 | Nama kapster, nama layanan, label harga |
| **Body Text** | 13–14 sp | Regular (w400) | 1.4 | Deskripsi alamat ruko, catatan layanan |
| **Caption / Muted** | 11–12 sp | Medium (w500) | 1.3 | Estimasi menit tunggu, label status antrean |
| **Badge / Micro** | 9–10 sp | Bold (w800) | 1.0 | Label "TIKET", indikator kursi fisik |

---

## 4. Sistem Spacing & Grid (8-Point Baseline Grid)

Seluruh jarak vertikal dan horizontal menggunakan kelipatan 4px / 8px untuk menjaga proporsi visual seragam:
- `4 dp` : Spacing mikro antar-elemen teks rapat (misal jarak judul ke caption).
- `8 dp` : Padding internal chip filter, margin horizontal ikon ke teks.
- `12 dp`: Jarak antar-kartu dalam list, padding horizontal input field.
- `16 dp`: Padding standar isi kartu (*card padding*), margin batas antar-bagian.
- `24 dp`: Padding horizontal layar utama (*screen margin*), jarak antar-seksi besar.
- `32 dp`: Jarak pemisah antar-langkah alur pemesanan (*step spacing*).

---

## 5. Bentuk Komponen & Kurva Sudut (Border Radius)
- **Tombol Aksi Utama (*CTA Buttons*):** Radius `12 dp` dengan tinggi minimum `48 dp`.
- **Kartu Barbershop & Antrean Aktif:** Radius `16 dp` dengan border subtle `1.5 dp`.
- **Lingkaran Avatar Kapster:** `Shape: BoxShape.circle` (ukuran 70x70 dp) dengan border emas saat status terpilih.
- **Lencana Tiket Emas (*Ticket Badge*):** Radius `10–12 dp` dengan kontras teks hitam di atas emas.

---

## 6. Standar Aksesibilitas UI/UX (WCAG 2.1 Level AA)
1. **Nama Aksesibel Wajib (*Accessible Names*):**  
   Setiap elemen `IconButton` wajib memiliki atribut `tooltip: 'Nama Tindakan'`.
2. **Tag Semantik Tombol Kustom:**  
   Elemen yang dapat disentuh (misal kartu tanggal atau pilihan kapster) wajib dibungkus dengan widget:
   `Semantics(button: true, selected: isSelected, label: '...')`.
3. **Bebas Jebakan Warna Murni (*Non-Color Sole Indicator*):**  
   Status antrean tidak boleh hanya dibedakan oleh warna titik hijau/kuning; wajib selalu disertai teks eksplisit (contoh: teks *"Menunggu"* atau *"Sedang Dipotong"*).
