import { query, pool } from './db.js';

export async function seedDatabase(): Promise<void> {
  console.log('🌱 Memulai seeding database relasional multi-tenant (v2.0)...');

  // 1. Bersihkan seluruh tabel
  await query(`
    TRUNCATE TABLE 
      queue_logs, payments, queue_reservations, 
      services, barbers, users, tenants 
    RESTART IDENTITY CASCADE;
  `);

  // 2. Insert 3 Tenants Barbershop Mitra
  const tenantRows = await query(`
    INSERT INTO tenants (slug, name, address, phone, chairs_count) VALUES
    ('febrian-barbershop', 'Febrian BarberShop', 'Jl. Pala Raya No.Desa, Kademangan, Mejasem Barat, Kec. Kramat, Kab. Tegal 52181', '087896903760', 4),
    ('rr-barber-studio', 'RR Barber Studio', 'Samping Big Laundry, Jl. Projosumarto 1, Kaladawa, Kec. Talang, Kab. Tegal 52193', '088226323086', 3),
    ('stupid-culture', 'Stupid Culture Barbershop', 'Jl. Kapten Ismail No. 20, Kota Tegal (depan SJT Custom)', '085727566125', 3)
    RETURNING id, slug, name;
  `);

  const tenantMap = new Map<string, number>();
  for (const row of tenantRows.rows as Array<{ id: number; slug: string; name: string }>) {
    tenantMap.set(row.slug, row.id);
  }

  const febrianId = tenantMap.get('febrian-barbershop')!;
  const rrId = tenantMap.get('rr-barber-studio')!;
  const stupidId = tenantMap.get('stupid-culture')!;

  // 3. Insert Users & Akun RBAC
  const userRows = await query(`
    INSERT INTO users (tenant_id, name, email, phone, role) VALUES
    -- Super Admin (Admin Root Kampus UHN)
    (NULL, 'M. Irsyad Fachryanto', 'irsyad@uhn.ac.id', '081234567899', 'super_admin'),
    -- Admin / Owner Febrian (Sekaligus Barberman di Kursi 2)
    ($1, 'Febri (Owner & Barber)', 'febri@febrianbarber.com', '087896903760', 'admin_owner'),
    ($1, 'Ferdi (Kapster Cepat)', 'ferdi@febrianbarber.com', '081200000001', 'barberman'),
    ($1, 'Hakim (Kapster Teliti)', 'hakim@febrianbarber.com', '081200000002', 'barberman'),
    -- Admin / Owner RR Studio
    ($2, 'Owner RR Studio', 'owner@rrbarber.com', '088226323086', 'admin_owner'),
    ($2, 'Kapster 1 RR', 'kapster1@rrbarber.com', '081200000003', 'barberman'),
    -- Admin / Owner Stupid Culture
    ($3, 'Owner Stupid Culture', 'owner@stupidculture.com', '085727566125', 'admin_owner'),
    ($3, 'Bagas (Kapster Cepat)', 'bagas@stupidculture.com', '081200000004', 'barberman'),
    ($3, 'Reno (Kapster Standar)', 'reno@stupidculture.com', '081200000005', 'barberman'),
    ($3, 'Danang (Kapster Teliti)', 'danang@stupidculture.com', '081200000006', 'barberman'),
    -- Customer Pelanggan
    (NULL, 'Dimas Pratama', 'dimas@gmail.com', '081299887766', 'customer')
    RETURNING id, name, role;
  `, [febrianId, rrId, stupidId]);

  const userMap = new Map<string, number>();
  for (const row of userRows.rows as Array<{ id: number; name: string; role: string }>) {
    userMap.set(row.name, row.id);
  }

  const febriUserId = userMap.get('Febri (Owner & Barber)');
  const ferdiUserId = userMap.get('Ferdi (Kapster Cepat)');
  const hakimUserId = userMap.get('Hakim (Kapster Teliti)');
  const bagasUserId = userMap.get('Bagas (Kapster Cepat)');
  const renoUserId = userMap.get('Reno (Kapster Standar)');
  const danangUserId = userMap.get('Danang (Kapster Teliti)');

  // 4. Insert Barbers dengan Tautan user_id (Febri adalah Admin Sekaligus Kapster)
  await query(`
    INSERT INTO barbers (tenant_id, user_id, name, chair_number, speed_factor, speed_val, is_on_duty, off_day_name) VALUES
    -- Febrian (Febri merangkap admin_owner & barberman)
    ($1, $4, 'Ferdi', 1, 0.85, 20.0, true, 'Senin'),
    ($1, $5, 'Febri', 2, 1.00, 30.0, true, 'Selasa'),
    ($1, $6, 'Hakim', 3, 1.20, 40.0, true, 'Rabu'),
    -- RR Barber Studio
    ($2, NULL, 'Kapster 1', 1, 1.00, 25.0, true, 'Kamis'),
    ($2, NULL, 'Kapster 2', 2, 1.20, 35.0, true, 'Jumat'),
    -- Stupid Culture
    ($3, $7, 'Bagas', 1, 0.85, 20.0, true, 'Senin'),
    ($3, $8, 'Reno', 2, 1.00, 30.0, true, 'Selasa'),
    ($3, $9, 'Danang', 3, 1.20, 35.0, true, 'Rabu');
  `, [febrianId, rrId, stupidId, ferdiUserId, febriUserId, hakimUserId, bagasUserId, renoUserId, danangUserId]);

  // 5. Insert Services per Tenant
  await query(`
    INSERT INTO services (tenant_id, name, price, complexity_score, base_duration_min, category) VALUES
    -- Febrian
    ($1, 'Potong Rambut Standar', 40000, 2.5, 25, 'ringan'),
    ($1, 'Skin Fade & Beard Sculpting', 45000, 5.5, 35, 'sedang'),
    ($1, 'Pewarnaan / Hair Color', 80000, 8.5, 60, 'tinggi'),
    -- RR Barber Studio
    ($2, 'Signature Haircut', 35000, 2.5, 30, 'ringan'),
    ($2, 'Fade Haircut', 40000, 5.5, 35, 'sedang'),
    ($2, 'Coloring / Bleaching', 75000, 8.5, 60, 'tinggi'),
    -- Stupid Culture
    ($3, 'Gentleman Haircut (AC)', 25000, 2.5, 25, 'ringan'),
    ($3, 'Taper / Skin Fade', 35000, 5.5, 35, 'sedang'),
    ($3, 'Hair Coloring / Cat', 65000, 8.5, 60, 'tinggi');
  `, [febrianId, rrId, stupidId]);

  // 6. Insert Riwayat Cukur Selesai untuk Kalibrasi MAE/MAPE (Dataset Skripsi Riil)
  await query(`
    INSERT INTO queue_reservations (
      tenant_id, ticket_number, customer_name, customer_phone,
      service_id, barber_id, booking_type, is_smart_dispatch,
      status, estimated_duration, estimated_start_time,
      actual_start_time, actual_end_time, actual_duration
    ) VALUES
    -- Febrian Barbershop (Completed Data)
    ($1, 'S-01', 'Rian Kurniawan', '081234567801', 1, 1, 'online_app', true, 'completed', 15, NOW() - INTERVAL '2 hours', NOW() - INTERVAL '2 hours', NOW() - INTERVAL '102 minutes', 18),
    ($1, 'S-02', 'Budi Santoso', '081234567802', 2, 2, 'online_app', true, 'completed', 35, NOW() - INTERVAL '90 minutes', NOW() - INTERVAL '90 minutes', NOW() - INTERVAL '56 minutes', 34),
    ($1, 'A-01', 'Hendra Setiawan', '081234567803', 3, 3, 'online_app', false, 'completed', 65, NOW() - INTERVAL '60 minutes', NOW() - INTERVAL '60 minutes', NOW() + INTERVAL '3 minutes', 63),
    -- RR Barber Studio (Completed Data)
    ($2, 'A-01', 'Wahyu Pratama', '081900000001', 4, 4, 'online_app', false, 'completed', 30, NOW() - INTERVAL '4 hours', NOW() - INTERVAL '4 hours', NOW() - INTERVAL '212 minutes', 28),
    -- Stupid Culture (Completed Data)
    ($3, 'S-01', 'Agus Wicaksono', '085727000001', 7, 6, 'online_app', true, 'completed', 15, NOW() - INTERVAL '3 hours', NOW() - INTERVAL '3 hours', NOW() - INTERVAL '161 minutes', 19),
    ($3, 'S-02', 'Fajar Ramadhan', '085727000002', 8, 7, 'online_app', true, 'completed', 35, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', NOW() - INTERVAL '24 minutes', 36);
  `, [febrianId, rrId, stupidId]);

  console.log('✅ Seeding relasional berhasil: 3 Tenant, 11 Users (RBAC), 8 Barbers, 9 Services, 5 Completed Reservations.');
}

if (process.argv[1]?.endsWith('seed.ts')) {
  seedDatabase()
    .then(() => pool.end())
    .catch((err: unknown) => {
      console.error('❌ Seeding gagal:', err);
      process.exit(1);
    });
}
