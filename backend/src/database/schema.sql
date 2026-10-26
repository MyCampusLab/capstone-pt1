-- ============================================================================
-- POSTGRESQL RELATIONAL MULTI-TENANT SCHEMA (SMARTBARBER ECOSYSTEM v2.0)
-- ACID Compliant, Strict Tenant Boundary Enforcement, and RBAC Ready
-- ============================================================================

-- Clean migration drops
DROP VIEW IF EXISTS v_skripsi_mae_mape, v_active_queue_board CASCADE;
DROP TABLE IF EXISTS queue_logs, payments, queue_reservations, services, barbers, users, tenants CASCADE;

-- 1. TABEL TENANTS (Mitra Barbershop Terverifikasi)
CREATE TABLE IF NOT EXISTS tenants (
    id SERIAL PRIMARY KEY,
    slug VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    address TEXT NOT NULL,
    phone VARCHAR(30) NOT NULL,
    chairs_count INT DEFAULT 3,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. TABEL USERS & RBAC (Role-Based Access Control)
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    tenant_id INT REFERENCES tenants(id) ON DELETE CASCADE, -- NULL untuk super_admin
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE,
    phone VARCHAR(30) NOT NULL,
    role VARCHAR(30) NOT NULL CHECK (role IN ('super_admin', 'admin_owner', 'barberman', 'customer')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_role ON users(role, tenant_id);

-- 3. TABEL BARBERS (Data Kapster & Kursi Pangkas)
CREATE TABLE IF NOT EXISTS barbers (
    id SERIAL PRIMARY KEY,
    tenant_id INT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE SET NULL, -- Tautan jika kapster punya akun login
    name VARCHAR(100) NOT NULL,
    chair_number INT NOT NULL,
    speed_factor NUMERIC(3, 2) DEFAULT 1.00,
    speed_val NUMERIC(4, 1) DEFAULT 30.0, -- Input Variabel X2 Fuzzy
    is_on_duty BOOLEAN DEFAULT TRUE,
    is_on_leave BOOLEAN DEFAULT FALSE,
    off_day_name VARCHAR(20) DEFAULT 'Minggu',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_tenant_chair UNIQUE (tenant_id, chair_number),
    CONSTRAINT uq_tenant_barber_composite UNIQUE (tenant_id, id)
);

-- 4. TABEL SERVICES (Katalog Menu Layanan per Cabang)
CREATE TABLE IF NOT EXISTS services (
    id SERIAL PRIMARY KEY,
    tenant_id INT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    price NUMERIC(12, 2) NOT NULL,
    complexity_score NUMERIC(3, 1) NOT NULL, -- Input Variabel X1 Fuzzy (1.0 - 10.0)
    base_duration_min INT NOT NULL,
    category VARCHAR(20) NOT NULL CHECK (category IN ('ringan', 'sedang', 'tinggi')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_tenant_service_composite UNIQUE (tenant_id, id)
);

-- 5. TABEL QUEUE_RESERVATIONS (Transaksi Antrean Atomik & Riwayat Durasi)
CREATE TABLE IF NOT EXISTS queue_reservations (
    id SERIAL PRIMARY KEY,
    tenant_id INT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    ticket_number VARCHAR(20) NOT NULL,
    customer_id INT REFERENCES users(id) ON DELETE SET NULL,
    customer_name VARCHAR(100) NOT NULL,
    customer_phone VARCHAR(30) NOT NULL,
    service_id INT NOT NULL,
    barber_id INT NOT NULL,
    booking_type VARCHAR(20) DEFAULT 'online_app' CHECK (booking_type IN ('online_app', 'walk_in')),
    is_smart_dispatch BOOLEAN DEFAULT FALSE,
    status VARCHAR(30) DEFAULT 'waiting' CHECK (status IN ('waiting', 'checked_in', 'in_service', 'completed', 'cancelled')),
    estimated_duration INT NOT NULL, -- Hasil Defuzifikasi Fuzzy Sugeno (Menit)
    estimated_start_time TIMESTAMP WITH TIME ZONE NOT NULL, -- Hasil Heuristik Smart Dispatch
    actual_start_time TIMESTAMP WITH TIME ZONE,
    actual_end_time TIMESTAMP WITH TIME ZONE,
    actual_duration INT, -- Durasi Nyata Hasil Pangkas (Menit) untuk Uji MAE/MAPE
    payment_proof_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- Isolasi Batas Tenant Ketat (Relasi Komposit Mencegah Booking Lintas Toko)
    CONSTRAINT fk_queue_tenant_barber FOREIGN KEY (tenant_id, barber_id) REFERENCES barbers(tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_queue_tenant_service FOREIGN KEY (tenant_id, service_id) REFERENCES services(tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_active_queues ON queue_reservations (tenant_id, barber_id, status);
CREATE INDEX IF NOT EXISTS idx_tenant_daily_queues ON queue_reservations (tenant_id, created_at);

-- 6. TABEL PAYMENTS (Pencatatan Keuangan & Verifikasi Kasir)
CREATE TABLE IF NOT EXISTS payments (
    id SERIAL PRIMARY KEY,
    reservation_id INT NOT NULL REFERENCES queue_reservations(id) ON DELETE CASCADE,
    amount NUMERIC(12, 2) NOT NULL,
    payment_method VARCHAR(30) DEFAULT 'cash' CHECK (payment_method IN ('cash', 'transfer_manual', 'qris')),
    proof_image_url TEXT,
    status VARCHAR(20) DEFAULT 'paid' CHECK (status IN ('pending', 'paid', 'verified', 'rejected')),
    verified_by_user_id INT REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 7. TABEL QUEUE_LOGS (Audit Trail Perubahan Status)
CREATE TABLE IF NOT EXISTS queue_logs (
    id SERIAL PRIMARY KEY,
    reservation_id INT NOT NULL REFERENCES queue_reservations(id) ON DELETE CASCADE,
    old_status VARCHAR(30),
    new_status VARCHAR(30) NOT NULL,
    actor VARCHAR(50) DEFAULT 'system',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================================
-- HELPER DATABASE VIEWS (Kueri Cepat Analitik & Antrean)
-- ============================================================================

-- View Papan Antrean Aktif
CREATE OR REPLACE VIEW v_active_queue_board AS
SELECT 
    q.id,
    q.tenant_id,
    t.name as tenant_name,
    t.slug as tenant_slug,
    q.ticket_number,
    q.customer_name,
    q.customer_phone,
    b.id as barber_id,
    b.name as barber_name,
    b.chair_number,
    s.name as service_name,
    s.price as service_price,
    q.booking_type,
    q.is_smart_dispatch,
    q.status,
    q.estimated_duration,
    q.estimated_start_time,
    q.created_at
FROM queue_reservations q
JOIN tenants t ON q.tenant_id = t.id
JOIN barbers b ON q.barber_id = b.id
JOIN services s ON q.service_id = s.id
WHERE q.status IN ('waiting', 'checked_in', 'in_service')
ORDER BY q.id ASC;

-- View Evaluasi Skripsi MAE & MAPE per Tenant
CREATE OR REPLACE VIEW v_skripsi_mae_mape AS
SELECT 
    q.tenant_id,
    t.name as tenant_name,
    t.slug as tenant_slug,
    COUNT(q.id) as sample_count,
    ROUND(AVG(ABS(q.actual_duration - q.estimated_duration)), 2) as mae_minutes,
    ROUND(AVG(ABS(q.actual_duration - q.estimated_duration)::numeric / NULLIF(q.actual_duration, 0) * 100), 2) as mape_percentage
FROM queue_reservations q
JOIN tenants t ON q.tenant_id = t.id
WHERE q.status = 'completed' AND q.actual_duration IS NOT NULL AND q.actual_duration > 0
GROUP BY q.tenant_id, t.name, t.slug;
