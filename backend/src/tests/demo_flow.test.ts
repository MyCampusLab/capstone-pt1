import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import type { Server } from 'node:http';
import { server } from '../server.js';

interface BookingResponse {
  ticketNumber: string;
  customerName: string;
  customerPhone: string;
  serviceName: string;
  assignedBarber: {
    id: number;
    name: string;
    chair: number;
  };
  isSmartDispatch: boolean;
  estimatedDurationMinutes: number;
  estimatedStartTime: string;
  status: string;
  bookingType: string;
}

interface UploadResponse {
  uploadUrl: string;
  fileKey: string;
  publicUrl: string;
}

describe('💈 Simulasi Alur Penuh (End-to-End Live Workflow 3 Mitra)', () => {
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

  test('Alur 1: Pelanggan booking di Febrian Barbershop dengan Smart Dispatch', async () => {
    const res = await fetch(`${BASE_URL}/api/queue/book`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        tenantSlug: 'febrian-barbershop',
        customerName: 'Ahmad Fauzi',
        customerPhone: '081234567899',
        serviceId: 1, // Potong Rambut Standar
        barberId: 'smart',
        bookingType: 'online_app',
      }),
    });

    assert.strictEqual(res.status, 201);
    const body = (await res.json()) as BookingResponse;
    assert.strictEqual(body.isSmartDispatch, true);
    assert.ok(body.ticketNumber.startsWith('S-'));
    assert.ok(body.assignedBarber.name.length > 0);
    assert.ok(body.estimatedDurationMinutes > 0);
  });

  test('Alur 2: Pelanggan booking di RR Barber Studio dengan Pemilihan Kapster Manual', async () => {
    const res = await fetch(`${BASE_URL}/api/queue/book`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        tenantSlug: 'rr-barber-studio',
        customerName: 'Budi Santoso',
        customerPhone: '081987654321',
        serviceId: 4, // Signature Haircut (RR Studio)
        barberId: 4, // Kapster 1
        bookingType: 'online_app',
      }),
    });

    assert.strictEqual(res.status, 201);
    const body = (await res.json()) as BookingResponse;
    assert.strictEqual(body.isSmartDispatch, false);
    assert.ok(body.ticketNumber.startsWith('A-'));
    assert.strictEqual(body.assignedBarber.id, 4);
  });

  test('Alur 3: Pelanggan booking di Stupid Culture Barbershop & Upload Bukti Bayar S3', async () => {
    // 1. Booking antrean
    const resBooking = await fetch(`${BASE_URL}/api/queue/book`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        tenantSlug: 'stupid-culture',
        customerName: 'Rian Permana',
        customerPhone: '085712345678',
        serviceId: 7, // Gentleman Haircut AC (Stupid Culture)
        barberId: 'smart',
        bookingType: 'online_app',
      }),
    });

    assert.strictEqual(resBooking.status, 201);
    const bodyBooking = (await resBooking.json()) as BookingResponse;
    assert.strictEqual(bodyBooking.isSmartDispatch, true);
    assert.ok(bodyBooking.ticketNumber.startsWith('S-'));

    // 2. Minta presigned URL upload S3
    const resUpload = await fetch(`${BASE_URL}/api/media/presign-upload`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        filename: 'bukti_transfer_bca_rian.jpg',
        contentType: 'image/jpeg',
      }),
    });

    assert.strictEqual(resUpload.status, 200);
    const bodyUpload = (await resUpload.json()) as UploadResponse;
    assert.ok(bodyUpload.uploadUrl.includes('barbershop-proofs'));
    assert.ok(bodyUpload.publicUrl.endsWith('.jpg'));
  });
});
