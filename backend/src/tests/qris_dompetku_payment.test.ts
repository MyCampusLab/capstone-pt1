import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import type { Server } from 'node:http';
import { server } from '../server.js';
import { query } from '../database/db.js';
import {
  computeCrc16Ccitt,
  validateStaticQris,
  generateDynamicQris,
  buildValidStaticQris,
  parseTlvNodes,
} from '../algorithms/emvcoQris.js';
import { computeDompetkuSignature } from '../routes/payment.routes.js';
import { FALLBACK_TENANTS } from '../types/models.js';
import { inMemoryPayments, inMemoryUnmatchedNotifications } from '../services/paymentAllocator.js';

interface BookingWithPaymentResponse {
  ticketNumber: string;
  customerName: string;
  serviceName: string;
  status: string;
  payment: {
    paymentId: number;
    baseAmount: number;
    uniqueCode: number;
    expectedAmount: number;
    qrisDynamicPayload: string | null;
    status: string;
    expiresAt: string;
  };
}

describe('⚡ Phase 1–4 E2E: EMVCo Dynamic QRIS & DompetKu Webhook Payment Bridge', () => {
  const BASE_URL = 'http://localhost:4000';
  let spawnedServer: Server | null = null;

  before(async () => {
    inMemoryPayments.length = 0;
    inMemoryUnmatchedNotifications.length = 0;
    try {
      await query(
        `DELETE FROM unmatched_payment_notifications WHERE dompetku_tx_id IN ('dk-tx-10001', 'dk-unmatched-40000')`
      );
      await query(
        `DELETE FROM payments WHERE dompetku_tx_id IN ('dk-tx-10001', 'dk-unmatched-40000') OR status = 'pending'`
      );
    } catch {}
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

  test('1. Mesin EMVCo QRIS: Validasi CRC16-CCITT & Konversi Statis (01=11) ke Dinamis (01=12 + Tag 54)', () => {
    const staticQris = buildValidStaticQris({
      nmid: 'ID1025000001001',
      merchantName: 'FEBRIAN BARBERSHOP',
      merchantCity: 'TEGAL',
      postalCode: '52181',
    });

    const validation = validateStaticQris(staticQris);
    assert.strictEqual(validation.valid, true, `Static QRIS harus valid: ${validation.reason}`);

    // Konversi ke nominal unik Rp 40.017
    const dynamicQris = generateDynamicQris(staticQris, 40017);
    const dynValidation = validateStaticQris(dynamicQris);
    assert.strictEqual(dynValidation.valid, true, 'Dynamic QRIS harus memiliki CRC16 valid');

    const nodes = parseTlvNodes(dynamicQris);
    const tag01 = nodes.find((n) => n.tag === '01');
    const tag54 = nodes.find((n) => n.tag === '54');
    assert.strictEqual(tag01?.value, '12', 'Tag 01 wajib berubah dari 11 (Statis) ke 12 (Dinamis)');
    assert.strictEqual(tag54?.value, '40017', 'Tag 54 wajib mengunci nominal 40017');

    // Pastikan CRC16 rusak terdeteksi
    const tampered = `${dynamicQris.slice(0, -4)}0000`;
    assert.strictEqual(validateStaticQris(tampered).valid, false);
    assert.strictEqual(computeCrc16Ccitt(dynamicQris.slice(0, -4)), dynamicQris.slice(-4));
  });

  test('2. Alokasi Kode Unik Anti-Bentrok (1..50) pada Booking Paralel di Barbershop yang Sama', async () => {
    const res1 = await fetch(`${BASE_URL}/api/queue/book`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        tenantSlug: 'febrian-barbershop',
        customerName: 'Pelanggan QRIS Satu',
        customerPhone: '081234560001',
        serviceId: 1, // Rp 40.000
        barberId: 'smart',
        bookingType: 'online_app',
      }),
    });
    assert.strictEqual(res1.status, 201);
    const b1 = (await res1.json()) as BookingWithPaymentResponse;

    const res2 = await fetch(`${BASE_URL}/api/queue/book`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        tenantSlug: 'febrian-barbershop',
        customerName: 'Pelanggan QRIS Dua',
        customerPhone: '081234560002',
        serviceId: 1, // Rp 40.000
        barberId: 'smart',
        bookingType: 'online_app',
      }),
    });
    assert.strictEqual(res2.status, 201);
    const b2 = (await res2.json()) as BookingWithPaymentResponse;

    assert.strictEqual(b1.payment.baseAmount, 40000);
    assert.strictEqual(b2.payment.baseAmount, 40000);
    assert.notStrictEqual(
      b1.payment.expectedAmount,
      b2.payment.expectedAmount,
      'Nominal unik 2 pesanan aktif di toko yang sama tidak boleh bentrok'
    );
    assert.ok(b1.payment.uniqueCode >= 1 && b1.payment.uniqueCode <= 50);
    assert.ok(b2.payment.uniqueCode >= 1 && b2.payment.uniqueCode <= 50);
    assert.ok(b1.payment.qrisDynamicPayload?.includes(`5405${b1.payment.expectedAmount}`));
  });

  test('3. Keamanan Webhook DompetKu: Tolak Signature Palsu (401) & Terima HMAC-SHA256 Asli + Idempotensi Retry', async () => {
    // Ambil pesanan pertama di febrian-barbershop
    const pendingTarget = inMemoryPayments.find(
      (p) => p.tenant_slug === 'febrian-barbershop' && p.status === 'pending'
    )!;
    assert.ok(pendingTarget, 'Harus ada pembayaran pending dari test sebelumnya');

    const febrianSecret = FALLBACK_TENANTS.find(
      (t) => t.slug === 'febrian-barbershop'
    )!.webhook_secret;

    const dompetkuPayloadObj = {
      message: JSON.stringify({
        id: 'dk-tx-10001',
        appSource: 'DANA',
        amount: pendingTarget.amount,
        formattedAmount: `Rp${pendingTarget.amount}`,
        payerName: 'Ahmad Kasir Test',
        type: 'dana_in',
        dateTime: new Date().toISOString(),
        rawMessage: `DANA: Kamu menerima Rp${pendingTarget.amount} dari Ahmad`,
      }),
      amount: pendingTarget.amount,
      id: 'dk-tx-10001',
      appSource: 'DANA',
    };
    const rawBody = JSON.stringify(dompetkuPayloadObj);
    const timestamp = String(Math.floor(Date.now() / 1000));

    // A. Uji Signature Salah -> Wajib 401 Unauthorized
    const badRes = await fetch(`${BASE_URL}/api/payments/webhook/febrian-barbershop`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Dompetku-Timestamp': timestamp,
        'X-Dompetku-Signature': '0000000000000000000000000000000000000000000000000000000000000000',
      },
      body: rawBody,
    });
    assert.strictEqual(badRes.status, 401);

    // B. Uji Signature HMAC-SHA256 Valid -> Wajib 200 OK & matched: true
    const validSig = computeDompetkuSignature(febrianSecret, timestamp, rawBody);
    const okRes = await fetch(`${BASE_URL}/api/payments/webhook/febrian-barbershop`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Dompetku-Timestamp': timestamp,
        'X-Dompetku-Signature': validSig,
      },
      body: rawBody,
    });
    assert.strictEqual(okRes.status, 200);
    const okBody = (await okRes.json()) as {
      matched: boolean;
      ticketNumber: string;
      amount: number;
      appSource: string;
    };
    assert.strictEqual(okBody.matched, true);
    assert.strictEqual(okBody.ticketNumber, pendingTarget.ticket_number);
    assert.strictEqual(okBody.amount, pendingTarget.amount);
    assert.strictEqual(okBody.appSource, 'DANA');

    // C. Uji Idempotensi: Kirim ulang txId yang sama -> Wajib 200 OK (idempotent: true), BUKAN 409
    const retryRes = await fetch(`${BASE_URL}/api/payments/webhook/febrian-barbershop`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Dompetku-Timestamp': timestamp,
        'X-Dompetku-Signature': validSig,
      },
      body: rawBody,
    });
    assert.strictEqual(retryRes.status, 200);
    const retryBody = (await retryRes.json()) as { idempotent: boolean; status: string };
    assert.strictEqual(retryBody.idempotent, true);
    assert.strictEqual(retryBody.status, 'already_processed');

    // D. Pastikan endpoint status tiket melaporkan 'verified'
    const statusRes = await fetch(
      `${BASE_URL}/api/payments/febrian-barbershop/status/${pendingTarget.ticket_number}`
    );
    assert.strictEqual(statusRes.status, 200);
    const statusBody = (await statusRes.json()) as { status: string; appSource: string };
    assert.strictEqual(statusBody.status, 'verified');
    assert.strictEqual(statusBody.appSource, 'DANA');
  });

  test('4. Filter Anti-Spoofing & Rekonsiliasi Manual Kasir untuk Nominal Meleset (Unmatched)', async () => {
    const febrianSecret = FALLBACK_TENANTS.find(
      (t) => t.slug === 'febrian-barbershop'
    )!.webhook_secret;
    const timestamp = String(Math.floor(Date.now() / 1000));

    // A. Transaksi keluar (dana_out) atau aplikasi SMS tidak dikenal wajib diabaikan
    const outPayload = JSON.stringify({
      id: 'dk-out-99',
      amount: 40002,
      appSource: 'DANA',
      type: 'dana_out',
    });
    const outSig = computeDompetkuSignature(febrianSecret, timestamp, outPayload);
    const outRes = await fetch(`${BASE_URL}/api/payments/webhook/febrian-barbershop`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Dompetku-Timestamp': timestamp,
        'X-Dompetku-Signature': outSig,
      },
      body: outPayload,
    });
    assert.strictEqual(outRes.status, 200);
    const outBody = (await outRes.json()) as { ignored: boolean };
    assert.strictEqual(outBody.ignored, true);

    // B. Pelanggan transfer nominal bulat Rp 40.000 (tanpa kode unik) -> Masuk Unmatched Queue
    const wrongAmtPayload = JSON.stringify({
      id: 'dk-unmatched-40000',
      amount: 40000,
      appSource: 'SeaBank',
      payerName: 'Budi Salah Ketik',
      type: 'seabank_in',
    });
    const wrongAmtSig = computeDompetkuSignature(febrianSecret, timestamp, wrongAmtPayload);
    const unmatchedRes = await fetch(`${BASE_URL}/api/payments/webhook/febrian-barbershop`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Dompetku-Timestamp': timestamp,
        'X-Dompetku-Signature': wrongAmtSig,
      },
      body: wrongAmtPayload,
    });
    assert.strictEqual(unmatchedRes.status, 200);
    const unmatchedBody = (await unmatchedRes.json()) as {
      matched: boolean;
      recordedAsUnmatched: boolean;
    };
    assert.strictEqual(unmatchedBody.matched, false);
    assert.strictEqual(unmatchedBody.recordedAsUnmatched, true);

    // C. Endpoint Admin (/dompetku-config & /verify-manual) wajib menolak akses tanpa x-admin-key (401)
    const unauthConfigRes = await fetch(
      `${BASE_URL}/api/payments/febrian-barbershop/dompetku-config`
    );
    assert.strictEqual(unauthConfigRes.status, 401);

    const authConfigRes = await fetch(
      `${BASE_URL}/api/payments/febrian-barbershop/dompetku-config`,
      { headers: { 'x-admin-key': 'smartbarber-admin-secret-key' } }
    );
    assert.strictEqual(authConfigRes.status, 200);

    const secondPending = inMemoryPayments.find(
      (p) => p.tenant_slug === 'febrian-barbershop' && p.status === 'pending'
    )!;
    const unauthVerifyRes = await fetch(
      `${BASE_URL}/api/payments/febrian-barbershop/verify-manual`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ticketNumber: secondPending.ticket_number,
          actor: 'kasir_febrian',
          unmatchedTxId: 'dk-unmatched-40000',
        }),
      }
    );
    assert.strictEqual(unauthVerifyRes.status, 401);

    // D. Kasir merekonsiliasi manual tiket kedua dengan x-admin-key valid (1-klik)
    const reconcileRes = await fetch(`${BASE_URL}/api/payments/febrian-barbershop/verify-manual`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-admin-key': 'smartbarber-admin-secret-key',
      },
      body: JSON.stringify({
        ticketNumber: secondPending.ticket_number,
        actor: 'kasir_febrian',
        unmatchedTxId: 'dk-unmatched-40000',
      }),
    });
    assert.strictEqual(reconcileRes.status, 200);
    const reconcileBody = (await reconcileRes.json()) as { success: boolean; status: string };
    assert.strictEqual(reconcileBody.success, true);
    assert.strictEqual(reconcileBody.status, 'verified');
  });
});
