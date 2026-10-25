import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import type { Server } from 'node:http';
import { server } from '../server.js';

interface WalkInResponse {
  id: number;
  ticketNumber: string;
  customerName: string;
  status: string;
  bookingType: string;
}

interface TransitionResponse {
  success: boolean;
  queueId: number;
  status: string;
}

interface MetricsResponse {
  tenantSlug: string;
  totalCompletedSample: number;
  maeMinutes: number;
  mapePercentage: number;
  evaluationStatus: string;
  workloadPerBarber: Array<{
    barberName: string;
    completedAppointments: number;
    totalMinutesWorked: number;
  }>;
}

describe('💈 Batch 1 E2E: Operasional Kasir, Transisi Cukur, & Analitik Skripsi', () => {
  const BASE_URL = 'http://localhost:4000';
  let spawnedServer: Server | null = null;

  before(async () => {
    try {
      const ping = await fetch(`${BASE_URL}/health`);
      if (ping.ok) return;
    } catch {
      spawnedServer = server.listen(4000);
      await once(spawnedServer, 'listening');
    }
  });

  after(() => {
    if (spawnedServer) {
      spawnedServer.close();
    }
  });

  test('Alur Penuh 1: Walk-in Kasir -> Cukur Selesai -> Data Masuk PostgreSQL', async () => {
    // 1. Pendaftaran walk-in kasir
    const resWalkIn = await fetch(`${BASE_URL}/api/cashier/walk-in`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        tenantSlug: 'febrian-barbershop',
        customerName: 'Pelanggan Walk-In Mejasem',
        customerPhone: '081234567888',
        serviceId: 1,
        barberId: 'smart',
      }),
    });

    assert.strictEqual(resWalkIn.status, 201);
    const walkInBody = (await resWalkIn.json()) as WalkInResponse;
    assert.ok(walkInBody.ticketNumber.startsWith('W-'));
    assert.strictEqual(walkInBody.bookingType, 'walk_in');

    const queueId = walkInBody.id;

    // 2. Kasir memanggil & mulai pangkas (in_service)
    const resStart = await fetch(`${BASE_URL}/api/cashier/queue/${queueId}/transition`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'in_service', actor: 'kasir_febrian' }),
    });
    assert.strictEqual(resStart.status, 200);
    const startBody = (await resStart.json()) as TransitionResponse;
    assert.strictEqual(startBody.status, 'in_service');

    // 3. Kasir menyelesaikan pangkas (completed)
    const resFinish = await fetch(`${BASE_URL}/api/cashier/queue/${queueId}/transition`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'completed', actor: 'kasir_febrian' }),
    });
    assert.strictEqual(resFinish.status, 200);
    const finishBody = (await resFinish.json()) as TransitionResponse;
    assert.strictEqual(finishBody.status, 'completed');
  });

  test('Alur Penuh 2: Endpoint Analitik Metrik Skripsi (MAE/MAPE) & Ekspor CSV', async () => {
    // 1. Kueri metrik analitik
    const resMetrics = await fetch(`${BASE_URL}/api/reports/febrian-barbershop/metrics`);
    assert.strictEqual(resMetrics.status, 200);
    const metrics = (await resMetrics.json()) as MetricsResponse;
    assert.strictEqual(metrics.tenantSlug, 'febrian-barbershop');
    assert.ok(typeof metrics.maeMinutes === 'number');
    assert.ok(typeof metrics.mapePercentage === 'number');

    // 2. Unduh berkas CSV untuk Bab 4 Skripsi
    const resCsv = await fetch(`${BASE_URL}/api/reports/febrian-barbershop/export-csv`);
    assert.strictEqual(resCsv.status, 200);
    assert.ok(resCsv.headers.get('content-type')?.includes('text/csv'));
    const csvText = await resCsv.text();
    assert.ok(csvText.includes('ID,Tenant,Tiket,Nama_Pelanggan'));
  });
});
