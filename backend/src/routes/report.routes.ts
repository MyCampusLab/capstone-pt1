import { Router, type Request, type Response } from 'express';
import { query } from '../database/db.js';

export const reportRouter = Router();

interface CompletedRecord {
  id: number;
  ticket_number: string;
  customer_name: string;
  barber_name: string;
  service_name: string;
  estimated_duration: number;
  actual_duration: number;
  created_at: Date;
}

reportRouter.get('/:tenantSlug/metrics', async (req: Request, res: Response) => {
  const { tenantSlug } = req.params;

  try {
    const qRes = await query(`
      SELECT q.id, q.ticket_number, q.customer_name,
             b.name as barber_name, s.name as service_name,
             q.estimated_duration, q.actual_duration, q.created_at
      FROM queue_reservations q
      JOIN tenants t ON q.tenant_id = t.id
      JOIN barbers b ON q.barber_id = b.id
      JOIN services s ON q.service_id = s.id
      WHERE t.slug = $1 AND q.actual_duration IS NOT NULL
      ORDER BY q.id ASC;
    `, [tenantSlug]);

    const records = qRes.rows as unknown as CompletedRecord[];
    const n = records.length;

    if (n === 0) {
      // Fallback response bila data cukur baru belum selesai
      res.json({
        tenantSlug,
        totalCompletedSample: 0,
        maeMinutes: 0.0,
        mapePercentage: 0.0,
        evaluationStatus: 'Menunggu transaksi cukur berstatus completed',
        workloadPerBarber: [],
      });
      return;
    }

    let totalAbsError = 0;
    let totalPctError = 0;
    const barberWorkloads = new Map<string, { count: number; totalMinutes: number }>();

    for (const r of records) {
      const absErr = Math.abs(r.actual_duration - r.estimated_duration);
      const pctErr = r.actual_duration > 0 ? (absErr / r.actual_duration) * 100 : 0;
      totalAbsError += absErr;
      totalPctError += pctErr;

      const current = barberWorkloads.get(r.barber_name) || { count: 0, totalMinutes: 0 };
      current.count += 1;
      current.totalMinutes += r.actual_duration;
      barberWorkloads.set(r.barber_name, current);
    }

    const MAE = Number((totalAbsError / n).toFixed(2));
    const MAPE = Number((totalPctError / n).toFixed(2));

    res.json({
      tenantSlug,
      totalCompletedSample: n,
      maeMinutes: MAE,
      mapePercentage: MAPE,
      evaluationStatus: MAPE < 15.0 ? 'Sangat Baik (Lolos Syarat Skripsi)' : 'Perlu Kalibrasi Bobot Fuzzy',
      workloadPerBarber: Array.from(barberWorkloads.entries()).map(([barberName, stats]) => ({
        barberName,
        completedAppointments: stats.count,
        totalMinutesWorked: stats.totalMinutes,
      })),
    });
  } catch {
    res.json({
      tenantSlug,
      totalCompletedSample: 0,
      maeMinutes: 0.0,
      mapePercentage: 0.0,
      evaluationStatus: 'Menunggu transaksi cukur berstatus completed (In-Memory Fallback)',
      workloadPerBarber: [],
    });
  }
});

reportRouter.get('/:tenantSlug/export-csv', async (req: Request, res: Response) => {
  const { tenantSlug } = req.params;

  try {
    const qRes = await query(`
      SELECT q.id, t.name as tenant_name, q.ticket_number, q.customer_name,
             b.name as barber_name, s.name as service_name,
             q.estimated_duration, q.actual_duration, q.created_at
      FROM queue_reservations q
      JOIN tenants t ON q.tenant_id = t.id
      JOIN barbers b ON q.barber_id = b.id
      JOIN services s ON q.service_id = s.id
      WHERE t.slug = $1 AND q.actual_duration IS NOT NULL
      ORDER BY q.id ASC;
    `, [tenantSlug]);

    const records = qRes.rows as unknown as (CompletedRecord & { tenant_name: string })[];

    let csvContent = 'ID,Tenant,Tiket,Nama_Pelanggan,Kapster,Layanan,Est_Durasi_Menit,Aktual_Durasi_Menit,Error_Absolut_Menit,Error_Persen,Tanggal\n';

    for (const r of records) {
      const absErr = Math.abs(r.actual_duration - r.estimated_duration);
      const pctErr = r.actual_duration > 0 ? (absErr / r.actual_duration) * 100 : 0;
      const dateStr = r.created_at ? new Date(r.created_at).toISOString().split('T')[0] : '';

      csvContent += `${r.id},"${r.tenant_name}",${r.ticket_number},"${r.customer_name}","${r.barber_name}","${r.service_name}",${r.estimated_duration},${r.actual_duration},${absErr.toFixed(2)},${pctErr.toFixed(2)}%,${dateStr}\n`;
    }

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename="evaluasi_skripsi_${tenantSlug}.csv"`);
    res.send(csvContent);
  } catch {
    const csvContent =
      'ID,Tenant,Tiket,Nama_Pelanggan,Kapster,Layanan,Est_Durasi_Menit,Aktual_Durasi_Menit,Error_Absolut_Menit,Error_Persen,Tanggal\n';
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename="evaluasi_skripsi_${tenantSlug}.csv"`);
    res.send(csvContent);
  }
});
