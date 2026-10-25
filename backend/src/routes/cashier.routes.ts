import { Router, type Request, type Response } from 'express';
import { type Server as SocketIOServer } from 'socket.io';
import { z } from 'zod';
import { query } from '../database/db.js';
import { FuzzySugenoQueueEstimator } from '../algorithms/fuzzySugeno.js';
import { SmartDispatchEngine, type ActiveBarber, type ActiveQueueItem } from '../algorithms/smartDispatch.js';
import { inMemoryQueues } from './queue.routes.js';

const walkInSchema = z.object({
  tenantSlug: z.string(),
  customerName: z.string().default('Pelanggan Walk-In'),
  customerPhone: z.string().default('080000000000'),
  serviceId: z.number().default(1),
  barberId: z.union([z.number(), z.literal('smart')]).default('smart'),
});

const transitionSchema = z.object({
  status: z.enum(['called', 'in_service', 'completed', 'cancelled']),
  actor: z.string().default('kasir'),
});

export function createCashierRouter(io: SocketIOServer): Router {
  const router = Router();

  // 1. Pendaftaran Walk-in Cepat (<10 Detik di Kasir Fisik)
  router.post('/walk-in', async (req: Request, res: Response) => {
    const parse = walkInSchema.safeParse(req.body);
    if (!parse.success) {
      res.status(400).json({ error: 'Data walk-in tidak valid', details: parse.error.format() });
      return;
    }

    const { tenantSlug, customerName, customerPhone, serviceId, barberId } = parse.data;

    let tenantId = 1;
    try {
      const tRes = await query('SELECT id FROM tenants WHERE slug = $1', [tenantSlug]);
      if (tRes.rows.length > 0) {
        const row = tRes.rows[0];
        if (row && typeof row === 'object' && 'id' in row && typeof row.id === 'number') {
          tenantId = row.id;
        }
      }
    } catch {}

    let serviceComplexity = 3.0;
    let baseDuration = 25;
    try {
      const sRes = await query('SELECT complexity_score, base_duration_min FROM services WHERE id = $1 AND tenant_id = $2', [serviceId, tenantId]);
      if (sRes.rows.length > 0) {
        const row = sRes.rows[0];
        if (row && typeof row === 'object' && 'complexity_score' in row && 'base_duration_min' in row) {
          serviceComplexity = Number(row.complexity_score);
          baseDuration = Number(row.base_duration_min);
        }
      }
    } catch {}

    let activeBarbers: ActiveBarber[] = [];
    try {
      const bRes = await query('SELECT id, name, chair_number, speed_factor, speed_val FROM barbers WHERE tenant_id = $1 AND is_on_duty = true ORDER BY chair_number', [tenantId]);
      activeBarbers = (bRes.rows as Array<{ id: number; name: string; chair_number: number; speed_factor?: string | number; speed_val?: string | number }>).map((b) => ({
        id: b.id,
        name: b.name,
        chair_number: b.chair_number,
        speed_factor: Number(b.speed_factor || 1.0),
        speed_val: Number(b.speed_val || 30.0),
      }));
    } catch {}

    if (activeBarbers.length === 0) {
      activeBarbers = [{ id: 1, name: 'Kapster Utama', chair_number: 1, speed_val: 25.0 }];
    }

    let assignedBarber = activeBarbers[0]!;
    let isSmart = false;

    if (barberId === 'smart') {
      isSmart = true;
      const alloc = SmartDispatchEngine.allocateQueue(activeBarbers, inMemoryQueues, baseDuration);
      assignedBarber = alloc.assignedBarber;
    } else {
      const found = activeBarbers.find((b) => b.id === barberId);
      if (found) assignedBarber = found;
    }

    const fuzzy = FuzzySugenoQueueEstimator.calculateDuration(serviceComplexity, assignedBarber.speed_val || 30.0);
    const estDuration = fuzzy.roundedDuration;
    const estStart = new Date().toISOString();

    let dailyCount = inMemoryQueues.length;
    try {
      const countRes = await query('SELECT COUNT(*) FROM queue_reservations WHERE tenant_id = $1 AND DATE(created_at) = CURRENT_DATE', [tenantId]);
      if (countRes.rows.length > 0) {
        const row = countRes.rows[0];
        if (row && typeof row === 'object' && 'count' in row) {
          dailyCount = Number(row.count);
        }
      }
    } catch {}

    const ticketNumber = `W-${String(dailyCount + 1).padStart(2, '0')}`;

    let resId = inMemoryQueues.length + 1;
    try {
      const insRes = await query(`
        INSERT INTO queue_reservations (
          tenant_id, ticket_number, customer_name, customer_phone,
          service_id, barber_id, booking_type, is_smart_dispatch,
          status, estimated_duration, estimated_start_time
        ) VALUES ($1, $2, $3, $4, $5, $6, 'walk_in', $7, 'checked_in', $8, $9)
        RETURNING id;
      `, [tenantId, ticketNumber, customerName, customerPhone, serviceId, assignedBarber.id, isSmart, estDuration, estStart]);

      if (insRes.rows.length > 0) {
        const row = insRes.rows[0];
        if (row && typeof row === 'object' && 'id' in row && typeof row.id === 'number') {
          resId = row.id;
        }
      }
    } catch {}

    const payload = {
      id: resId,
      ticketNumber,
      customerName,
      assignedBarber: { id: assignedBarber.id, name: assignedBarber.name, chair: assignedBarber.chair_number },
      estimatedDurationMinutes: estDuration,
      status: 'checked_in',
      bookingType: 'walk_in',
    };

    io.emit(`queue:${tenantSlug}:updated`, payload);
    res.status(201).json(payload);
  });

  // 2. Transisi Status Antrean Kasir (Panggil, Mulai Potong, Selesai Cukur)
  router.post('/queue/:id/transition', async (req: Request, res: Response) => {
    const queueId = Number(req.params.id);
    const parse = transitionSchema.safeParse(req.body);
    if (!parse.success) {
      res.status(400).json({ error: 'Status transisi tidak valid', details: parse.error.format() });
      return;
    }

    const { status, actor } = parse.data;
    const now = new Date();

    try {
      if (status === 'in_service') {
        await query(`
          UPDATE queue_reservations 
          SET status = 'in_service', actual_start_time = $2 
          WHERE id = $1;
        `, [queueId, now]);
      } else if (status === 'completed') {
        // Hitung durasi aktual (menit) jika actual_start_time ada
        const qRow = await query('SELECT actual_start_time FROM queue_reservations WHERE id = $1', [queueId]);
        let actualMinutes = 25;
        if (qRow.rows.length > 0) {
          const row = qRow.rows[0];
          if (row && typeof row === 'object' && 'actual_start_time' in row && row.actual_start_time instanceof Date) {
            actualMinutes = Math.max(1, Math.round((now.getTime() - row.actual_start_time.getTime()) / 60000));
          }
        }
        await query(`
          UPDATE queue_reservations 
          SET status = 'completed', actual_end_time = $2, actual_duration = $3 
          WHERE id = $1;
        `, [queueId, now, actualMinutes]);
      } else {
        await query('UPDATE queue_reservations SET status = $2 WHERE id = $1', [queueId, status]);
      }

      await query('INSERT INTO queue_logs (reservation_id, new_status, actor) VALUES ($1, $2, $3)', [queueId, status, actor]);

      io.emit('queue:status:changed', { queueId, status, timestamp: now.toISOString() });
      res.json({ success: true, queueId, status, timestamp: now.toISOString() });
    } catch {
      // Fallback update in-memory
      const local = inMemoryQueues.find((q) => q.id === queueId);
      if (local) local.status = status;
      res.json({ success: true, queueId, status, note: 'updated in-memory' });
    }
  });

  return router;
}
