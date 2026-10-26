import { Router, type Request, type Response } from 'express';
import { type Server as SocketIOServer } from 'socket.io';
import { z } from 'zod';
import { query } from '../database/db.js';
import { FuzzySugenoQueueEstimator } from '../algorithms/fuzzySugeno.js';
import { SmartDispatchEngine, type ActiveBarber, type ActiveQueueItem } from '../algorithms/smartDispatch.js';
import { FALLBACK_TENANTS, FALLBACK_BARBERS, FALLBACK_SERVICES } from '../types/models.js';
import { createSlidingWindowLimiter } from '../middleware/rateLimiter.js';

const bookingRateLimiter = createSlidingWindowLimiter(60_000, 15);

export const inMemoryQueues: ActiveQueueItem[] = [];

const fuzzyPreviewSchema = z.object({
  complexityScore: z.number().min(1.0).max(10.0),
  barberAvgDuration: z.number().min(15.0).max(45.0),
});

const bookingSchema = z.object({
  tenantSlug: z.string(),
  customerName: z.string().min(2),
  customerPhone: z.string().min(8),
  serviceId: z.number(),
  barberId: z.union([z.number(), z.literal('smart')]).default('smart'),
  bookingType: z.enum(['online_app', 'walk_in']).default('online_app'),
});

export function createQueueRouter(io: SocketIOServer): Router {
  const router = Router();

  router.post('/preview', (req: Request, res: Response) => {
    const parseResult = fuzzyPreviewSchema.safeParse(req.body);
    if (!parseResult.success) {
      res.status(400).json({ error: 'Parameter tidak valid', details: parseResult.error.format() });
      return;
    }

    const { complexityScore, barberAvgDuration } = parseResult.data;
    const result = FuzzySugenoQueueEstimator.calculateDuration(complexityScore, barberAvgDuration);
    res.json(result);
  });

  router.post('/book', bookingRateLimiter, async (req: Request, res: Response) => {
    const parseResult = bookingSchema.safeParse(req.body);
    if (!parseResult.success) {
      res.status(400).json({ error: 'Data booking tidak valid', details: parseResult.error.format() });
      return;
    }

    const { tenantSlug, customerName, customerPhone, serviceId, barberId, bookingType } = parseResult.data;

    let tenantId = 1;
    try {
      const tRes = await query('SELECT id, name FROM tenants WHERE slug = $1', [tenantSlug]);
      if (tRes.rows.length > 0) {
        const row = tRes.rows[0];
        if (row && typeof row === 'object' && 'id' in row && typeof row.id === 'number') {
          tenantId = row.id;
        }
      } else {
        const tFallback = FALLBACK_TENANTS.find((t) => t.slug === tenantSlug);
        if (tFallback) tenantId = tFallback.id;
      }
    } catch {
      const tFallback = FALLBACK_TENANTS.find((t) => t.slug === tenantSlug);
      if (tFallback) tenantId = tFallback.id;
    }

    let serviceComplexity = 3.0;
    let serviceName = 'Layanan Terpilih';
    let serviceFound = false;

    try {
      const sRes = await query('SELECT id, name, complexity_score FROM services WHERE id = $1 AND tenant_id = $2', [serviceId, tenantId]);
      if (sRes.rows.length > 0) {
        const row = sRes.rows[0];
        if (row && typeof row === 'object' && 'name' in row && 'complexity_score' in row) {
          serviceComplexity = Number(row.complexity_score);
          serviceName = String(row.name);
          serviceFound = true;
        }
      }
    } catch {}

    if (!serviceFound) {
      const sFallback = FALLBACK_SERVICES.find((s) => s.id === serviceId && s.tenant_id === tenantId);
      if (sFallback) {
        serviceComplexity = sFallback.complexity_score;
        serviceName = sFallback.name;
        serviceFound = true;
      }
    }

    if (!serviceFound) {
      res.status(400).json({ error: 'Layanan yang dipilih tidak tersedia di barbershop ini.' });
      return;
    }

    let activeBarbers: ActiveBarber[] = [];
    try {
      const bRes = await query('SELECT id, name, chair_number, speed_factor, speed_val FROM barbers WHERE tenant_id = $1 AND is_on_duty = true ORDER BY chair_number', [tenantId]);
      if (bRes.rows.length > 0) {
        activeBarbers = (bRes.rows as Array<{ id: number; name: string; chair_number: number; speed_factor?: string | number; speed_val?: string | number }>).map((b) => ({
          id: b.id,
          name: b.name,
          chair_number: b.chair_number,
          speed_factor: Number(b.speed_factor || 1.0),
          speed_val: Number(b.speed_val || 30.0),
        }));
      }
    } catch {}
    if (activeBarbers.length === 0) {
      activeBarbers = FALLBACK_BARBERS
        .filter((b) => b.tenant_id === tenantId)
        .map((b) => ({
          id: b.id,
          name: b.name,
          chair_number: b.chair_number,
          speed_factor: b.speed_factor,
          speed_val: b.speed_val,
        }));
    }

    let currentActiveQueues: ActiveQueueItem[] = [];
    try {
      const qRes = await query(`
        SELECT id, barber_id, status, estimated_duration, estimated_start_time
        FROM queue_reservations
        WHERE tenant_id = $1 AND status IN ('waiting', 'checked_in', 'in_service')
        ORDER BY id
      `, [tenantId]);
      currentActiveQueues = (qRes.rows as Array<{ id: number; barber_id: number; status: string; estimated_duration: number; estimated_start_time: Date | string }>).map((q) => ({
        id: q.id,
        barber_id: q.barber_id,
        status: q.status,
        estimated_duration: q.estimated_duration,
        estimated_start_time: q.estimated_start_time,
      }));
    } catch {
      currentActiveQueues = inMemoryQueues;
    }

    let assignedBarber: ActiveBarber;
    let estimatedDuration: number;
    let estimatedStartTime: string;
    let isSmartDispatch = false;

    if (barberId === 'smart') {
      isSmartDispatch = true;
      const baselineFuzzy = FuzzySugenoQueueEstimator.calculateDuration(serviceComplexity, 30.0);
      const dispatchResult = SmartDispatchEngine.allocateQueue(
        activeBarbers,
        currentActiveQueues,
        baselineFuzzy.roundedDuration
      );

      assignedBarber = dispatchResult.assignedBarber;
      estimatedStartTime = dispatchResult.estimatedStartTime;
      const specificFuzzy = FuzzySugenoQueueEstimator.calculateDuration(
        serviceComplexity,
        assignedBarber.speed_val || 30.0
      );
      estimatedDuration = specificFuzzy.roundedDuration;
    } else {
      const specific = activeBarbers.find((b) => b.id === barberId);
      if (!specific) {
        res.status(400).json({ error: 'Kapster yang dipilih tidak aktif.' });
        return;
      }
      assignedBarber = specific;
      const fuzzy = FuzzySugenoQueueEstimator.calculateDuration(
        serviceComplexity,
        assignedBarber.speed_val || 30.0
      );
      estimatedDuration = fuzzy.roundedDuration;
      estimatedStartTime = new Date().toISOString();
    }

    const ticketPrefix = isSmartDispatch ? 'S' : 'A';
    let dailySequence = currentActiveQueues.length + 1;
    try {
      const countRes = await query(
        'SELECT COUNT(*) FROM queue_reservations WHERE tenant_id = $1 AND DATE(created_at) = CURRENT_DATE',
        [tenantId]
      );
      if (countRes.rows.length > 0) {
        const row = countRes.rows[0];
        if (row && typeof row === 'object' && 'count' in row) {
          dailySequence = Number(row.count) + 1;
        }
      }
    } catch {}
    const ticketNumber = `${ticketPrefix}-${String(dailySequence).padStart(2, '0')}`;

    let dbReservationId = inMemoryQueues.length + 1;
    try {
      const insertRes = await query(`
        INSERT INTO queue_reservations (
          tenant_id, ticket_number, customer_name, customer_phone,
          service_id, barber_id, booking_type, is_smart_dispatch,
          status, estimated_duration, estimated_start_time
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        RETURNING id;
      `, [
        tenantId, ticketNumber, customerName, customerPhone,
        serviceId, assignedBarber.id, bookingType, isSmartDispatch,
        'waiting', estimatedDuration, estimatedStartTime
      ]);
      if (insertRes.rows.length > 0) {
        const row = insertRes.rows[0];
        if (row && typeof row === 'object' && 'id' in row && typeof row.id === 'number') {
          dbReservationId = row.id;
        }
      }
    } catch {}

    const newReservation: ActiveQueueItem = {
      id: dbReservationId,
      barber_id: assignedBarber.id,
      status: 'waiting',
      estimated_duration: estimatedDuration,
      estimated_start_time: estimatedStartTime,
    };

    inMemoryQueues.push(newReservation);
    if (inMemoryQueues.length > 50) {
      inMemoryQueues.splice(0, inMemoryQueues.length - 50);
    }

    const responsePayload = {
      ticketNumber,
      customerName,
      customerPhone,
      serviceName,
      assignedBarber: {
        id: assignedBarber.id,
        name: assignedBarber.name,
        chair: assignedBarber.chair_number,
      },
      isSmartDispatch,
      estimatedDurationMinutes: estimatedDuration,
      estimatedStartTime,
      status: 'waiting',
      bookingType,
    };

    io.emit(`queue:${tenantSlug}:updated`, responsePayload);
    res.status(201).json(responsePayload);
  });
  router.get('/ticket/:tenantSlug/:ticketNumber', async (req: Request, res: Response) => {
    const { tenantSlug, ticketNumber } = req.params;

    try {
      const qRes = await query(`
        SELECT q.id, q.ticket_number, q.customer_name, q.status,
               q.estimated_duration, q.estimated_start_time,
               b.id as barber_id, b.name as barber_name, b.chair_number,
               s.name as service_name
        FROM queue_reservations q
        JOIN tenants t ON q.tenant_id = t.id
        JOIN barbers b ON q.barber_id = b.id
        JOIN services s ON q.service_id = s.id
        WHERE t.slug = $1 AND q.ticket_number = $2
        ORDER BY q.id DESC
        LIMIT 1;
      `, [tenantSlug, ticketNumber]);

      if (qRes.rows.length > 0) {
        res.json(qRes.rows[0]);
        return;
      }
    } catch {}

    res.status(404).json({ error: 'Tiket antrean tidak ditemukan.' });
  });


  return router;
}
