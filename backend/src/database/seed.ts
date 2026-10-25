import { query, pool } from './db.js';

export async function seedDatabase(): Promise<void> {
  console.log('🌱 Memulai seeding database multi-tenant (3 Barbershop Mitra)...');

  // 1. Buat / bersihkan data awal
  await query(`
    TRUNCATE TABLE queue_logs, queue_reservations, services, barbers, tenants RESTART IDENTITY CASCADE;
  `);

  // 2. Insert 3 Barbershop Mitra
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

  // 3. Insert Barbers untuk masing-masing tenant
  // Febrian: Ferdi (Cepat), Febri (Standar), Hakim (Teliti)
  await query(`
    INSERT INTO barbers (tenant_id, name, chair_number, speed_factor, speed_val) VALUES
    ($1, 'Ferdi', 1, 0.85, 20.0),
    ($1, 'Febri', 2, 1.00, 30.0),
    ($1, 'Hakim', 3, 1.20, 40.0),
    ($2, 'Kapster 1', 1, 1.00, 25.0),
    ($2, 'Kapster 2', 2, 1.20, 35.0),
    ($3, 'Bagas', 1, 0.85, 20.0),
    ($3, 'Reno', 2, 1.00, 30.0),
    ($3, 'Danang', 3, 1.20, 35.0);
  `, [febrianId, rrId, stupidId]);

  // 4. Insert Services untuk masing-masing tenant
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

  console.log('✅ Seeding berhasil: 3 Tenant, 8 Kapster, 9 Layanan terpasang.');
}

if (process.argv[1]?.endsWith('seed.ts')) {
  seedDatabase()
    .then(() => pool.end())
    .catch((err: unknown) => {
      console.error('❌ Seeding gagal:', err);
      process.exit(1);
    });
}
