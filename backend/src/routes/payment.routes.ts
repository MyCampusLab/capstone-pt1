import crypto from 'node:crypto';
import type http from 'node:http';
import { Router, type Request, type Response } from 'express';
import { type Server as SocketIOServer } from 'socket.io';
import { z } from 'zod';
import { query } from '../database/db.js';
import { env } from '../config/env.js';
import { FALLBACK_TENANTS } from '../types/models.js';
import { validateStaticQris } from '../algorithms/emvcoQris.js';
import {
  inMemoryPayments,
  inMemoryUnmatchedNotifications,
  expireStalePendingPayments,
  type PaymentRecord,
} from '../services/paymentAllocator.js';
import { inMemoryQueues } from './queue.routes.js';

/**
 * Whitelist resmi aplikasi finansial & e-wallet Indonesia yang diizinkan
 * oleh jembatan DompetKu (Mitigasi Risiko #5: Anti-Spoofed SMS/Chat Notification).
 */
export const ALLOWED_DOMPETKU_APP_SOURCES: Record<string, true> = {
  dana: true,
  gopay: true,
  ovo: true,
  shopeepay: true,
  seabank: true,
  bca: true,
  'bca mobile': true,
  mybca: true,
  mandiri: true,
  livin: true,
  'livin by mandiri': true,
  bri: true,
  brimo: true,
  bni: true,
  wondr: true,
  'wondr by bni': true,
  jago: true,
  'bank jago': true,
  jenius: true,
  neobank: true,
  linkaja: true,
  octo: true,
  permata: true,
  qris: true,
};

/**
 * Menghitung HMAC-SHA256 sesuai kontrak DompetKu: hmac_sha256(secret, "$timestamp.$rawBody")
 */
export function computeDompetkuSignature(secret: string, timestamp: string, rawBody: string): string {
  return crypto.createHmac('sha256', secret).update(`${timestamp}.${rawBody}`, 'utf8').digest('hex');
}

function safeCompareStrings(a: string, b: string): boolean {
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

function requireAdminKey(req: Request, res: Response, tenantSecret: string): boolean {
  const candidate = (req.header('x-admin-key') || req.header('x-dompetku-secret') || '').trim();
  if (
    candidate &&
    (safeCompareStrings(candidate, env.ADMIN_API_KEY) || safeCompareStrings(candidate, tenantSecret))
  ) {
    return true;
  }
  res.status(401).json({ error: 'Unauthorized: Missing or invalid x-admin-key.' });
  return false;
}

function toPaymentStatusDto(r: Record<string, unknown> | PaymentRecord) {
  return {
    paymentId: r.id,
    reservationId: r.reservation_id,
    ticketNumber: r.ticket_number,
    baseAmount: Number(r.base_amount),
    uniqueCode: Number(r.unique_code),
    expectedAmount: Number(r.amount),
    qrisDynamicPayload: r.qris_dynamic_payload,
    paymentMethod: r.payment_method,
    proofImageUrl: r.proof_image_url,
    status: r.status,
    dompetkuTxId: r.dompetku_tx_id,
    appSource: r.app_source,
    payerName: r.payer_name,
    expiresAt: r.expires_at,
    verifiedAt: r.verified_at,
  };
}

/**
 * Memverifikasi autentikasi webhook DompetKu:
 * 1. Header HMAC-SHA256 (X-Dompetku-Timestamp + X-Dompetku-Signature) dengan batas anti-replay ±300 detik.
 * 2. Fallback token rahasia tenant via header x-dompetku-secret atau query ?secret= untuk Ping Test / Simulator DompetKu.
 */
export function verifyDompetkuWebhookAuth(params: {
  rawBody: string;
  timestampHeader?: string;
  signatureHeader?: string;
  secretHeader?: string;
  secretQuery?: string;
  tenantSecret: string;
}): { authorized: boolean; reason?: string } {
  const { rawBody, timestampHeader, signatureHeader, secretHeader, secretQuery, tenantSecret } = params;

  if (signatureHeader && timestampHeader) {
    const tsSeconds = Number(timestampHeader);
    if (!Number.isFinite(tsSeconds)) {
      return { authorized: false, reason: 'X-Dompetku-Timestamp bukan angka epoch detik yang valid.' };
    }
    const nowSeconds = Math.floor(Date.now() / 1000);
    if (Math.abs(nowSeconds - tsSeconds) > 300) {
      return { authorized: false, reason: 'X-Dompetku-Timestamp kedaluwarsa (> 300 detik).' };
    }

    const expectedSig = computeDompetkuSignature(tenantSecret, timestampHeader, rawBody);
    const cleanActual = signatureHeader.replace(/^sha256=/i, '').trim().toLowerCase();
    if (safeCompareStrings(cleanActual, expectedSig.toLowerCase())) {
      return { authorized: true };
    }
    return { authorized: false, reason: 'X-Dompetku-Signature HMAC-SHA256 tidak cocok.' };
  }

  const candidateToken = (secretHeader || secretQuery || '').trim();
  if (candidateToken && safeCompareStrings(candidateToken, tenantSecret)) {
    return { authorized: true };
  }

  return {
    authorized: false,
    reason: 'Missing or invalid DompetKu HMAC signature / webhook secret.',
  };
}

interface ParsedDompetkuEvent {
  txId: string;
  amount: number;
  appSource: string;
  payerName: string;
  txType: string;
  rawMessage: string;
}

/**
 * Mem-parse payload fleksibel DompetKu (mendukung format json_string di dalam key "message" maupun raw JSON).
 */
export function parseDompetkuPayload(body: unknown): ParsedDompetkuEvent | null {
  if (!body || typeof body !== 'object') return null;
  const top = body as Record<string, unknown>;

  let inner: Record<string, unknown> = top;
  if (typeof top.message === 'string' && top.message.trim().startsWith('{')) {
    try {
      const parsedInner = JSON.parse(top.message) as unknown;
      if (parsedInner && typeof parsedInner === 'object') {
        inner = { ...top, ...(parsedInner as Record<string, unknown>) };
      }
    } catch {}
  }

  const rawAmount = inner.amount ?? top.amount;
  const amount = Math.round(Number(rawAmount));
  if (!Number.isFinite(amount) || amount <= 0) {
    return null;
  }

  const txId = String(inner.id ?? top.id ?? `dk-${Date.now()}-${amount}`).trim();
  const appSource = String(inner.appSource ?? top.appSource ?? 'QRIS').trim();
  const payerName = String(inner.payerName ?? top.payerName ?? 'Pelanggan QRIS').trim();
  const txType = String(inner.type ?? top.type ?? 'qris_in').trim().toLowerCase();
  const rawMessage = String(
    inner.rawMessage ?? (typeof top.message === 'string' ? top.message : JSON.stringify(top))
  );

  return {
    txId,
    amount,
    appSource,
    payerName,
    txType,
    rawMessage,
  };
}

async function resolveTenantConfig(tenantSlug: string): Promise<{
  id: number;
  slug: string;
  name: string;
  qris_raw_payload: string;
  webhook_secret: string;
} | null> {
  const fallback = FALLBACK_TENANTS.find((t) => t.slug === tenantSlug);
  try {
    const dbRes = await query(
      'SELECT id, slug, name, qris_raw_payload, webhook_secret FROM tenants WHERE slug = $1',
      [tenantSlug]
    );
    if (dbRes.rows.length > 0) {
      const row = dbRes.rows[0];
      if (row && typeof row === 'object' && 'id' in row && 'slug' in row && 'name' in row) {
        const qrisRaw =
          'qris_raw_payload' in row && typeof row.qris_raw_payload === 'string'
            ? row.qris_raw_payload
            : fallback?.qris_raw_payload || '';
        const secret =
          'webhook_secret' in row && typeof row.webhook_secret === 'string'
            ? row.webhook_secret
            : fallback?.webhook_secret || 'dompetku-secret-key';
        return {
          id: Number(row.id),
          slug: String(row.slug),
          name: String(row.name),
          qris_raw_payload: qrisRaw,
          webhook_secret: secret,
        };
      }
    }
  } catch {}

  if (!fallback) return null;
  return {
    id: fallback.id,
    slug: fallback.slug,
    name: fallback.name,
    qris_raw_payload: fallback.qris_raw_payload,
    webhook_secret: fallback.webhook_secret,
  };
}

const manualProofSchema = z.object({
  ticketNumber: z.string().min(2),
  proofImageUrl: z.string().min(5),
});

const verifyManualSchema = z.object({
  ticketNumber: z.string().min(2),
  actor: z.string().default('kasir_manual'),
  unmatchedTxId: z.string().optional(),
});

const updateQrisSchema = z.object({
  qrisRawPayload: z.string().min(24),
});

export function createPaymentRouter(io: SocketIOServer): Router {
  const router = Router();

  // 1. Endpoint Jembatan Webhook DompetKu -> Backend Geges
  router.post('/webhook/:tenantSlug', async (req: Request, res: Response) => {
    const tenantSlug = String(req.params.tenantSlug || '');
    const tenant = await resolveTenantConfig(tenantSlug);
    if (!tenant) {
      res.status(404).json({ error: 'Tenant barbershop tidak ditemukan.' });
      return;
    }

    const reqWithRaw = req as http.IncomingMessage & { rawBody?: string };
    const rawBody =
      typeof reqWithRaw.rawBody === 'string' ? reqWithRaw.rawBody : JSON.stringify(req.body ?? {});

    const authCheck = verifyDompetkuWebhookAuth({
      rawBody,
      timestampHeader: req.header('x-dompetku-timestamp') ?? undefined,
      signatureHeader: req.header('x-dompetku-signature') ?? undefined,
      secretHeader: req.header('x-dompetku-secret') ?? undefined,
      secretQuery: typeof req.query.secret === 'string' ? req.query.secret : undefined,
      tenantSecret: tenant.webhook_secret,
    });

    if (!authCheck.authorized) {
      res.status(401).json({ error: 'Unauthorized DompetKu webhook', reason: authCheck.reason });
      return;
    }

    const parsed = parseDompetkuPayload(req.body);
    if (!parsed) {
      res.status(200).json({ ignored: true, reason: 'non_financial_or_ping_payload' });
      return;
    }

    const normalizedSource = parsed.appSource.toLowerCase().trim();
    if (parsed.txType.endsWith('_out') || !ALLOWED_DOMPETKU_APP_SOURCES[normalizedSource]) {
      res.status(200).json({
        ignored: true,
        reason: 'non_incoming_or_untrusted_source',
        appSource: parsed.appSource,
        type: parsed.txType,
      });
      return;
    }

    await expireStalePendingPayments(tenant.id);

    // Cek Idempotensi: Apakah dompetku_tx_id sudah pernah diproses?
    const alreadyInMemPayment = inMemoryPayments.find((p) => p.dompetku_tx_id === parsed.txId);
    const alreadyInMemUnmatched = inMemoryUnmatchedNotifications.find(
      (u) => u.dompetku_tx_id === parsed.txId
    );
    if (alreadyInMemPayment || alreadyInMemUnmatched) {
      res.status(200).json({
        status: 'already_processed',
        idempotent: true,
        dompetkuTxId: parsed.txId,
      });
      return;
    }

    try {
      const dupRes = await query(
        `
        SELECT id FROM payments WHERE dompetku_tx_id = $1
        UNION ALL
        SELECT id FROM unmatched_payment_notifications WHERE dompetku_tx_id = $1
        LIMIT 1;
        `,
        [parsed.txId]
      );
      if (dupRes.rows.length > 0) {
        res.status(200).json({
          status: 'already_processed',
          idempotent: true,
          dompetkuTxId: parsed.txId,
        });
        return;
      }
    } catch {}

    // Cari pembayaran pending dengan expectedAmount == parsed.amount di tenant ini
    const nowIso = new Date().toISOString();
    let matchedPayment: PaymentRecord | undefined = inMemoryPayments.find(
      (p) =>
        p.tenant_id === tenant.id &&
        p.status === 'pending' &&
        Math.round(p.amount) === parsed.amount &&
        new Date(p.expires_at).getTime() > Date.now()
    );

    if (matchedPayment) {
      matchedPayment.status = 'verified';
      matchedPayment.dompetku_tx_id = parsed.txId;
      matchedPayment.app_source = parsed.appSource;
      matchedPayment.payer_name = parsed.payerName;
      matchedPayment.verified_at = nowIso;

      const memQueue = inMemoryQueues.find((q) => q.id === matchedPayment!.reservation_id);
      if (memQueue && memQueue.status === 'waiting') {
        memQueue.status = 'checked_in';
      }
    }

    try {
      const dbMatch = await query(
        `
        UPDATE payments
        SET status = 'verified',
            dompetku_tx_id = $1,
            app_source = $2,
            payer_name = $3,
            verified_at = NOW()
        WHERE id = (
          SELECT id FROM payments
          WHERE tenant_id = $4 AND status = 'pending' AND amount = $5 AND expires_at > NOW()
          ORDER BY created_at ASC
          LIMIT 1
        )
        RETURNING id, reservation_id, base_amount, unique_code, amount;
        `,
        [parsed.txId, parsed.appSource, parsed.payerName, tenant.id, parsed.amount]
      );

      if (dbMatch.rows.length > 0) {
        const row = dbMatch.rows[0];
        if (
          row &&
          typeof row === 'object' &&
          'id' in row &&
          'reservation_id' in row &&
          'base_amount' in row &&
          'unique_code' in row &&
          'amount' in row
        ) {
          const reservationId = Number(row.reservation_id);
          await query(
            `UPDATE queue_reservations SET status = 'checked_in' WHERE id = $1 AND status = 'waiting'`,
            [reservationId]
          );
          await query(
            `INSERT INTO queue_logs (reservation_id, old_status, new_status, actor) VALUES ($1, 'waiting', 'checked_in', 'dompetku_webhook')`,
            [reservationId]
          );

          if (!matchedPayment) {
            const qTicket = await query(
              `SELECT ticket_number FROM queue_reservations WHERE id = $1`,
              [reservationId]
            );
            const firstTicketRow = qTicket.rows[0];
            const ticketStr =
              firstTicketRow &&
              typeof firstTicketRow === 'object' &&
              'ticket_number' in firstTicketRow &&
              typeof firstTicketRow.ticket_number === 'string'
                ? firstTicketRow.ticket_number
                : 'S-01';

            matchedPayment = {
              id: Number(row.id),
              tenant_id: tenant.id,
              tenant_slug: tenant.slug,
              reservation_id: reservationId,
              ticket_number: ticketStr,
              base_amount: Number(row.base_amount),
              unique_code: Number(row.unique_code),
              amount: Number(row.amount),
              qris_dynamic_payload: null,
              payment_method: 'qris',
              proof_image_url: null,
              status: 'verified',
              dompetku_tx_id: parsed.txId,
              app_source: parsed.appSource,
              payer_name: parsed.payerName,
              expires_at: nowIso,
              verified_at: nowIso,
            };
          }
        }
      }
    } catch {}

    if (matchedPayment) {
      const eventPayload = {
        tenantSlug: tenant.slug,
        reservationId: matchedPayment.reservation_id,
        ticketNumber: matchedPayment.ticket_number,
        amount: matchedPayment.amount,
        baseAmount: matchedPayment.base_amount,
        uniqueCode: matchedPayment.unique_code,
        appSource: parsed.appSource,
        payerName: parsed.payerName,
        dompetkuTxId: parsed.txId,
        verifiedAt: nowIso,
      };

      io.emit('payment:verified', eventPayload);
      io.emit(`queue:${tenant.slug}:updated`, {
        id: matchedPayment.reservation_id,
        ticketNumber: matchedPayment.ticket_number,
        status: 'checked_in',
        paymentStatus: 'verified',
      });

      res.status(200).json({
        matched: true,
        ...eventPayload,
      });
      return;
    }

    // Jika tidak cocok (misal pelanggan transfer nominal bulat tanpa kode unik)
    const unmatchedItem = {
      id: inMemoryUnmatchedNotifications.length + 1,
      tenant_id: tenant.id,
      tenant_slug: tenant.slug,
      dompetku_tx_id: parsed.txId,
      amount: parsed.amount,
      app_source: parsed.appSource,
      payer_name: parsed.payerName,
      raw_message: parsed.rawMessage,
      is_reconciled: false,
      reconciled_reservation_id: null,
      created_at: nowIso,
    };
    inMemoryUnmatchedNotifications.push(unmatchedItem);
    if (inMemoryUnmatchedNotifications.length > 200) {
      inMemoryUnmatchedNotifications.splice(0, inMemoryUnmatchedNotifications.length - 200);
    }

    try {
      await query(
        `
        INSERT INTO unmatched_payment_notifications (
          tenant_id, dompetku_tx_id, amount, app_source, payer_name, raw_message
        ) VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (dompetku_tx_id) DO NOTHING;
        `,
        [
          tenant.id,
          parsed.txId,
          parsed.amount,
          parsed.appSource,
          parsed.payerName,
          parsed.rawMessage,
        ]
      );
    } catch {}

    io.emit(`payment:${tenant.slug}:unmatched`, unmatchedItem);

    res.status(200).json({
      matched: false,
      recordedAsUnmatched: true,
      dompetkuTxId: parsed.txId,
      amount: parsed.amount,
      appSource: parsed.appSource,
    });
  });

  // 2. Cek Status Pembayaran per Tiket
  router.get('/:tenantSlug/status/:ticketNumber', async (req: Request, res: Response) => {
    const { tenantSlug, ticketNumber } = req.params;
    const mem = [...inMemoryPayments]
      .reverse()
      .find((p) => p.tenant_slug === tenantSlug && p.ticket_number === ticketNumber);

    try {
      const dbRes = await query(
        `
        SELECT p.id, p.reservation_id, q.ticket_number, p.base_amount, p.unique_code,
               p.amount, p.qris_dynamic_payload, p.payment_method, p.proof_image_url,
               p.status, p.dompetku_tx_id, p.app_source, p.payer_name, p.expires_at, p.verified_at
        FROM payments p
        JOIN queue_reservations q ON p.reservation_id = q.id
        JOIN tenants t ON p.tenant_id = t.id
        WHERE t.slug = $1 AND q.ticket_number = $2
        ORDER BY p.id DESC
        LIMIT 1;
        `,
        [tenantSlug, ticketNumber]
      );
      if (dbRes.rows.length > 0) {
        res.json(toPaymentStatusDto(dbRes.rows[0] as Record<string, unknown>));
        return;
      }
    } catch {}

    if (mem) {
      res.json(toPaymentStatusDto(mem));
      return;
    }

    res.status(404).json({ error: 'Data pembayaran untuk tiket tersebut tidak ditemukan.' });
  });

  // 3. Daftar Notifikasi Uang Masuk Belum Tercocokkan (Unmatched Notifications)
  router.get('/:tenantSlug/unmatched', async (req: Request, res: Response) => {
    const tenantSlug = String(req.params.tenantSlug || '');
    const tenant = await resolveTenantConfig(tenantSlug);
    if (!tenant) {
      res.status(404).json({ error: 'Tenant tidak ditemukan.' });
      return;
    }
    if (!requireAdminKey(req, res, tenant.webhook_secret)) return;

    try {
      const dbRes = await query(
        `
        SELECT id, dompetku_tx_id, amount, app_source, payer_name, raw_message, is_reconciled, created_at
        FROM unmatched_payment_notifications
        WHERE tenant_id = $1 AND is_reconciled = false
        ORDER BY id DESC;
        `,
        [tenant.id]
      );
      if (dbRes.rows.length > 0) {
        res.json(dbRes.rows);
        return;
      }
    } catch {}

    const list = inMemoryUnmatchedNotifications.filter(
      (u) => u.tenant_slug === tenantSlug && !u.is_reconciled
    );
    res.json(list);
  });

  // 4. Fallback Upload Bukti Transfer Manual oleh Pelanggan
  router.post('/:tenantSlug/manual-proof', async (req: Request, res: Response) => {
    const tenantSlug = String(req.params.tenantSlug || '');
    const parse = manualProofSchema.safeParse(req.body);
    if (!parse.success) {
      res.status(400).json({ error: 'Data bukti pembayaran tidak valid.', details: parse.error.format() });
      return;
    }
    const { ticketNumber, proofImageUrl } = parse.data;

    const mem = [...inMemoryPayments]
      .reverse()
      .find((p) => p.tenant_slug === tenantSlug && p.ticket_number === ticketNumber);
    if (mem) {
      mem.proof_image_url = proofImageUrl;
      mem.payment_method = 'transfer_manual';
      mem.status = 'paid';
    }

    try {
      await query(
        `
        UPDATE payments p
        SET proof_image_url = $1, payment_method = 'transfer_manual', status = 'paid'
        FROM queue_reservations q, tenants t
        WHERE p.reservation_id = q.id AND p.tenant_id = t.id
          AND t.slug = $2 AND q.ticket_number = $3;
        `,
        [proofImageUrl, tenantSlug, ticketNumber]
      );
    } catch {}

    io.emit(`payment:${tenantSlug}:manual_proof`, { ticketNumber, proofImageUrl });
    res.json({ success: true, ticketNumber, status: 'paid', proofImageUrl });
  });

  // 5. Konfirmasi / Rekonsiliasi Manual oleh Kasir (1-Klik)
  router.post('/:tenantSlug/verify-manual', async (req: Request, res: Response) => {
    const tenantSlug = String(req.params.tenantSlug || '');
    const tenant = await resolveTenantConfig(tenantSlug);
    if (!tenant) {
      res.status(404).json({ error: 'Tenant tidak ditemukan.' });
      return;
    }
    if (!requireAdminKey(req, res, tenant.webhook_secret)) return;

    const parse = verifyManualSchema.safeParse(req.body);
    if (!parse.success) {
      res.status(400).json({ error: 'Parameter verifikasi manual tidak valid.', details: parse.error.format() });
      return;
    }

    const { ticketNumber, actor, unmatchedTxId } = parse.data;
    const nowIso = new Date().toISOString();

    const mem = [...inMemoryPayments]
      .reverse()
      .find((p) => p.tenant_slug === tenantSlug && p.ticket_number === ticketNumber);

    if (mem) {
      mem.status = 'verified';
      mem.verified_at = nowIso;
      if (unmatchedTxId) {
        const unmatched = inMemoryUnmatchedNotifications.find(
          (u) => u.dompetku_tx_id === unmatchedTxId
        );
        if (unmatched) {
          unmatched.is_reconciled = true;
          unmatched.reconciled_reservation_id = mem.reservation_id;
          mem.dompetku_tx_id = unmatched.dompetku_tx_id;
          mem.app_source = unmatched.app_source;
          mem.payer_name = unmatched.payer_name;
        }
      }
      const memQueue = inMemoryQueues.find((q) => q.id === mem.reservation_id);
      if (memQueue && memQueue.status === 'waiting') {
        memQueue.status = 'checked_in';
      }
    }

    try {
      const qRes = await query(
        `
        UPDATE payments p
        SET status = 'verified', verified_at = NOW()
        FROM queue_reservations q, tenants t
        WHERE p.reservation_id = q.id AND p.tenant_id = t.id
          AND t.slug = $1 AND q.ticket_number = $2
        RETURNING p.reservation_id;
        `,
        [tenantSlug, ticketNumber]
      );
      if (qRes.rows.length > 0) {
        const firstRow = qRes.rows[0];
        if (
          firstRow &&
          typeof firstRow === 'object' &&
          'reservation_id' in firstRow &&
          typeof firstRow.reservation_id === 'number'
        ) {
          const reservationId = firstRow.reservation_id;
          await query(
            `UPDATE queue_reservations SET status = 'checked_in' WHERE id = $1 AND status = 'waiting'`,
            [reservationId]
          );
          await query(
            `INSERT INTO queue_logs (reservation_id, old_status, new_status, actor) VALUES ($1, 'waiting', 'checked_in', $2)`,
            [reservationId, actor]
          );
          if (unmatchedTxId) {
            await query(
              `UPDATE unmatched_payment_notifications SET is_reconciled = true, reconciled_reservation_id = $1 WHERE dompetku_tx_id = $2`,
              [reservationId, unmatchedTxId]
            );
          }
        }
      }
    } catch {}

    io.emit('payment:verified', {
      tenantSlug,
      ticketNumber,
      verifiedBy: actor,
      unmatchedTxId: unmatchedTxId ?? null,
      verifiedAt: nowIso,
    });

    res.json({
      success: true,
      tenantSlug,
      ticketNumber,
      status: 'verified',
      verifiedBy: actor,
      unmatchedTxId: unmatchedTxId ?? null,
    });
  });

  // 6. Konfigurasi Smart Paste DompetKu & Update QRIS Statis Mitra
  router.get('/:tenantSlug/dompetku-config', async (req: Request, res: Response) => {
    const tenantSlug = String(req.params.tenantSlug || '');
    const tenant = await resolveTenantConfig(tenantSlug);
    if (!tenant) {
      res.status(404).json({ error: 'Tenant tidak ditemukan.' });
      return;
    }
    if (!requireAdminKey(req, res, tenant.webhook_secret)) return;

    const host = req.get('host') || 'localhost:4000';
    const protocol = req.protocol || 'http';
    const webhookUrl = `${protocol}://${host}/api/payments/webhook/${tenant.slug}`;

    res.json({
      tenantSlug: tenant.slug,
      tenantName: tenant.name,
      qrisRawPayload: tenant.qris_raw_payload,
      webhookUrl,
    });
  });

  router.put('/:tenantSlug/qris-config', async (req: Request, res: Response) => {
    const tenantSlug = String(req.params.tenantSlug || '');
    const tenant = await resolveTenantConfig(tenantSlug);
    if (!tenant) {
      res.status(404).json({ error: 'Tenant tidak ditemukan.' });
      return;
    }
    if (!requireAdminKey(req, res, tenant.webhook_secret)) return;

    const parse = updateQrisSchema.safeParse(req.body);
    if (!parse.success) {
      res.status(400).json({ error: 'Payload QRIS tidak valid.', details: parse.error.format() });
      return;
    }

    const { qrisRawPayload } = parse.data;
    const check = validateStaticQris(qrisRawPayload);
    if (!check.valid) {
      res.status(400).json({ error: check.reason });
      return;
    }

    const fallback = FALLBACK_TENANTS.find((t) => t.slug === tenantSlug);
    if (fallback) {
      fallback.qris_raw_payload = qrisRawPayload.trim();
    }

    try {
      await query(`UPDATE tenants SET qris_raw_payload = $1 WHERE slug = $2`, [
        qrisRawPayload.trim(),
        tenantSlug,
      ]);
    } catch {}

    res.json({
      success: true,
      tenantSlug,
      qrisRawPayload: qrisRawPayload.trim(),
    });
  });

  return router;
}
