import { query } from './db.js';

export interface DbTenant {
  id: number;
  slug: string;
  name: string;
  address: string;
  phone: string;
  chairs_count: number;
}

export interface DbBarber {
  id: number;
  tenant_id: number;
  user_id?: number | null;
  name: string;
  chair_number: number;
  speed_factor: number;
  speed_val: number;
  is_on_duty: boolean;
  is_on_leave: boolean;
}

export interface DbService {
  id: number;
  tenant_id: number;
  name: string;
  price: number;
  complexity_score: number;
  base_duration_min: number;
  category: 'ringan' | 'sedang' | 'tinggi';
}

export interface ActiveQueueRow {
  id: number;
  tenant_id: number;
  ticket_number: string;
  customer_name: string;
  customer_phone: string;
  barber_id: number;
  barber_name: string;
  chair_number: number;
  service_name: string;
  service_price: number;
  booking_type: string;
  is_smart_dispatch: boolean;
  status: string;
  estimated_duration: number;
  estimated_start_time: Date;
  created_at: Date;
}

export interface SkripsiEvaluationRow {
  tenant_id: number;
  tenant_name: string;
  tenant_slug: string;
  sample_count: number;
  mae_minutes: number;
  mape_percentage: number;
}

export class BarbershopDbHelper {
  static async findTenantBySlug(slug: string): Promise<DbTenant | null> {
    const res = await query('SELECT id, slug, name, address, phone, chairs_count FROM tenants WHERE slug = $1 AND is_active = true', [slug]);
    if (res.rows.length === 0) return null;
    const r = res.rows[0];
    if (r && typeof r === 'object' && 'id' in r && 'name' in r) {
      return r as unknown as DbTenant;
    }
    return null;
  }

  static async findBarbersByTenant(tenantId: number): Promise<DbBarber[]> {
    const res = await query(
      'SELECT id, tenant_id, user_id, name, chair_number, speed_factor, speed_val, is_on_duty, is_on_leave ' +
      'FROM barbers WHERE tenant_id = $1 AND is_on_duty = true AND is_on_leave = false ' +
      'ORDER BY chair_number',
      [tenantId]
    );
    return res.rows as unknown as DbBarber[];
  }

  static async findServicesByTenant(tenantId: number): Promise<DbService[]> {
    const res = await query(
      'SELECT id, tenant_id, name, price, complexity_score, base_duration_min, category ' +
      'FROM services WHERE tenant_id = $1 AND is_active = true ' +
      'ORDER BY id',
      [tenantId]
    );
    return res.rows as unknown as DbService[];
  }

  static async getActiveQueueBoard(tenantId: number): Promise<ActiveQueueRow[]> {
    const res = await query(
      'SELECT * FROM v_active_queue_board WHERE tenant_id = $1',
      [tenantId]
    );
    return res.rows as unknown as ActiveQueueRow[];
  }

  static async getSkripsiMetrics(tenantSlug: string): Promise<SkripsiEvaluationRow | null> {
    const res = await query(
      'SELECT * FROM v_skripsi_mae_mape WHERE tenant_slug = $1',
      [tenantSlug]
    );
    if (res.rows.length === 0) return null;
    return res.rows[0] as unknown as SkripsiEvaluationRow;
  }
}
