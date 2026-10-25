import { Router, type Request, type Response } from 'express';
import { query } from '../database/db.js';
import { FALLBACK_TENANTS, FALLBACK_BARBERS, FALLBACK_SERVICES } from '../types/models.js';

export const tenantRouter = Router();

tenantRouter.get('/', async (_req: Request, res: Response) => {
  try {
    const dbRes = await query('SELECT id, slug, name, address, phone, chairs_count FROM tenants WHERE is_active = true ORDER BY id');
    if (dbRes.rows.length > 0) {
      res.json(dbRes.rows);
      return;
    }
  } catch {}
  res.json(FALLBACK_TENANTS);
});

tenantRouter.get('/:slug/catalog', async (req: Request, res: Response) => {
  const { slug } = req.params;

  try {
    const tenantRes = await query('SELECT id, slug, name FROM tenants WHERE slug = $1', [slug]);
    if (tenantRes.rows.length > 0) {
      const tenant = tenantRes.rows[0] as { id: number; slug: string; name: string };
      const [barbersRes, servicesRes] = await Promise.all([
        query('SELECT id, name, chair_number, speed_factor, speed_val, is_on_duty FROM barbers WHERE tenant_id = $1 AND is_on_duty = true', [tenant.id]),
        query('SELECT id, name, price, complexity_score, base_duration_min, category FROM services WHERE tenant_id = $1 AND is_active = true', [tenant.id]),
      ]);

      res.json({
        tenant,
        barbers: barbersRes.rows,
        services: servicesRes.rows,
      });
      return;
    }
  } catch {}

  const tenantFallback = FALLBACK_TENANTS.find((t) => t.slug === slug);
  if (!tenantFallback) {
    res.status(404).json({ error: 'Tenant barbershop tidak ditemukan.' });
    return;
  }

  const barbers = FALLBACK_BARBERS.filter((b) => b.tenant_id === tenantFallback.id);
  const services = FALLBACK_SERVICES.filter((s) => s.tenant_id === tenantFallback.id);

  res.json({
    tenant: tenantFallback,
    barbers,
    services,
  });
});
