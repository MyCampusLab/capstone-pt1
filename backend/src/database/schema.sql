-- PostgreSQL Multi-Tenant Database Schema for SmartBarber Ecosystem
-- Complies with ACID principles and eliminates race conditions via atomic locks

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

CREATE TABLE IF NOT EXISTS barbers (
    id SERIAL PRIMARY KEY,
    tenant_id INT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    chair_number INT NOT NULL,
    speed_factor NUMERIC(3, 2) DEFAULT 1.00,
    speed_val NUMERIC(4, 1) DEFAULT 30.0,
    is_on_duty BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uq_tenant_chair UNIQUE (tenant_id, chair_number)
);

CREATE TABLE IF NOT EXISTS services (
    id SERIAL PRIMARY KEY,
    tenant_id INT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    price NUMERIC(12, 2) NOT NULL,
    complexity_score NUMERIC(3, 1) NOT NULL,
    base_duration_min INT NOT NULL,
    category VARCHAR(20) NOT NULL CHECK (category IN ('ringan', 'sedang', 'tinggi')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS queue_reservations (
    id SERIAL PRIMARY KEY,
    tenant_id INT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    ticket_number VARCHAR(20) NOT NULL,
    customer_name VARCHAR(100) NOT NULL,
    customer_phone VARCHAR(30) NOT NULL,
    service_id INT NOT NULL REFERENCES services(id),
    barber_id INT NOT NULL REFERENCES barbers(id),
    booking_type VARCHAR(20) DEFAULT 'online_app' CHECK (booking_type IN ('online_app', 'walk_in')),
    is_smart_dispatch BOOLEAN DEFAULT FALSE,
    status VARCHAR(30) DEFAULT 'waiting' CHECK (status IN ('waiting', 'checked_in', 'in_service', 'completed', 'cancelled')),
    estimated_duration INT NOT NULL,
    estimated_start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    actual_start_time TIMESTAMP WITH TIME ZONE,
    actual_end_time TIMESTAMP WITH TIME ZONE,
    actual_duration INT,
    payment_proof_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_active_queues ON queue_reservations (tenant_id, barber_id, status);

CREATE TABLE IF NOT EXISTS queue_logs (
    id SERIAL PRIMARY KEY,
    reservation_id INT NOT NULL REFERENCES queue_reservations(id) ON DELETE CASCADE,
    old_status VARCHAR(30),
    new_status VARCHAR(30) NOT NULL,
    actor VARCHAR(50) DEFAULT 'system',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
