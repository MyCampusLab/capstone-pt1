import { query } from '../database/db.js';
import { generateDynamicQris, validateStaticQris } from '../algorithms/emvcoQris.js';

export interface PaymentRecord {
  id: number;
  tenant_id: number;
  tenant_slug: string;
  reservation_id: number;
  ticket_number: string;
  base_amount: number;
  unique_code: number;
  amount: number;
  qris_dynamic_payload: string | null;
  payment_method: 'cash' | 'transfer_manual' | 'qris';
  proof_image_url: string | null;
  status: 'pending' | 'paid' | 'verified' | 'rejected' | 'expired';
  dompetku_tx_id: string | null;
  app_source: string | null;
  payer_name: string | null;
  expires_at: string;
  verified_at: string | null;
}

export interface UnmatchedNotificationRecord {
  id: number;
  tenant_id: number;
  tenant_slug: string;
  dompetku_tx_id: string;
  amount: number;
  app_source: string;
  payer_name: string | null;
  raw_message: string | null;
  is_reconciled: boolean;
  reconciled_reservation_id: number | null;
  created_at: string;
}

export const inMemoryPayments: PaymentRecord[] = [];
export const inMemoryUnmatchedNotifications: UnmatchedNotificationRecord[] = [];

/**
 * Menandai seluruh pembayaran pending yang sudah melewati expires_at menjadi expired.
 */
export async function expireStalePendingPayments(tenantId: number): Promise<void> {
  const nowMs = Date.now();
  for (const p of inMemoryPayments) {
    if (p.tenant_id === tenantId && p.status === 'pending' && new Date(p.expires_at).getTime() <= nowMs) {
      p.status = 'expired';
    }
  }
  try {
    await query(
      `UPDATE payments SET status = 'expired' WHERE tenant_id = $1 AND status = 'pending' AND expires_at <= NOW()`,
      [tenantId]
    );
  } catch {}
}

/**
 * Mengalokasikan kode unik (1..50, fallback 51..999) sedemikian sehingga
 * expectedAmount = baseAmount + uniqueCode dijamin TIDAK BENTROK dengan
 * pembayaran 'pending' aktif mana pun pada tenant yang sama (termasuk lintas layanan).
 */
export async function allocateUniquePayment(params: {
  tenantId: number;
  tenantSlug: string;
  qrisRawPayload?: string | null;
  reservationId: number;
  ticketNumber: string;
  baseAmount: number;
}): Promise<PaymentRecord> {
  const { tenantId, tenantSlug, qrisRawPayload, reservationId, ticketNumber, baseAmount } = params;
  const cleanBase = Math.max(0, Math.round(baseAmount));

  await expireStalePendingPayments(tenantId);

  const nowMs = Date.now();
  const activePendingAmounts = new Set<number>();

  // 1. Kumpulkan seluruh amount aktif dari in-memory
  for (const p of inMemoryPayments) {
    if (
      p.tenant_id === tenantId &&
      p.status === 'pending' &&
      new Date(p.expires_at).getTime() > nowMs
    ) {
      activePendingAmounts.add(Math.round(p.amount));
    }
  }

  // 2. Kumpulkan seluruh amount aktif dari PostgreSQL jika tersedia
  try {
    const dbRes = await query(
      `SELECT amount FROM payments WHERE tenant_id = $1 AND status = 'pending' AND expires_at > NOW()`,
      [tenantId]
    );
    for (const row of dbRes.rows as Array<{ amount: string | number }>) {
      activePendingAmounts.add(Math.round(Number(row.amount)));
    }
  } catch {}

  // 3. Pilih kode unik terkecil mulai 1..50 (fallback 51..999) dengan retry atomik jika bentrok 23505 di PostgreSQL
  const expiresAt = new Date(nowMs + 15 * 60_000).toISOString();
  let chosenCode = 1;
  let expectedAmount = cleanBase + 1;
  let qrisDynamicPayload: string | null = null;
  let dbPaymentId = inMemoryPayments.length + 1;
  const isQrisValid = Boolean(qrisRawPayload && validateStaticQris(qrisRawPayload).valid);

  for (let attempt = 0; attempt < 5; attempt++) {
    chosenCode = 1;
    for (let code = 1; code <= 999; code++) {
      const candidateAmount = cleanBase + code;
      if (!activePendingAmounts.has(candidateAmount)) {
        chosenCode = code;
        break;
      }
    }

    expectedAmount = cleanBase + chosenCode;
    qrisDynamicPayload =
      isQrisValid && qrisRawPayload ? generateDynamicQris(qrisRawPayload, expectedAmount) : null;

    try {
      const insRes = await query(
        `
        INSERT INTO payments (
          tenant_id, reservation_id, base_amount, unique_code, amount,
          qris_dynamic_payload, payment_method, status, expires_at
        ) VALUES ($1, $2, $3, $4, $5, $6, 'qris', 'pending', $7)
        RETURNING id;
        `,
        [tenantId, reservationId, cleanBase, chosenCode, expectedAmount, qrisDynamicPayload, expiresAt]
      );
      if (insRes.rows.length > 0) {
        const row = insRes.rows[0] as { id?: number };
        if (typeof row.id === 'number') {
          dbPaymentId = row.id;
        }
      }
      break;
    } catch (err) {
      const pgCode =
        err && typeof err === 'object' && 'code' in err ? String((err as { code?: unknown }).code) : '';
      if (pgCode === '23505') {
        activePendingAmounts.add(expectedAmount);
        continue;
      }
      break;
    }
  }
  const record: PaymentRecord = {
    id: dbPaymentId,
    tenant_id: tenantId,
    tenant_slug: tenantSlug,
    reservation_id: reservationId,
    ticket_number: ticketNumber,
    base_amount: cleanBase,
    unique_code: chosenCode,
    amount: expectedAmount,
    qris_dynamic_payload: qrisDynamicPayload,
    payment_method: 'qris',
    proof_image_url: null,
    status: 'pending',
    dompetku_tx_id: null,
    app_source: null,
    payer_name: null,
    expires_at: expiresAt,
    verified_at: null,
  };

  inMemoryPayments.push(record);
  if (inMemoryPayments.length > 200) {
    inMemoryPayments.splice(0, inMemoryPayments.length - 200);
  }

  return record;
}
