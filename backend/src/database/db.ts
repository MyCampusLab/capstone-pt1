import { setTimeout } from 'timers/promises';
import pg from 'pg';
import { env } from '../config/env.js';

const { Pool } = pg;

export const pool = new Pool({
  connectionString: env.DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 3000,
});

pool.on('error', (err) => {
  console.error('[DB] PostgreSQL pool idle client error:', err);
});

let lastConnFailureAt = 0;
const OFFLINE_COOLDOWN_MS = 3000;

export async function query(text: string, params?: unknown[], retries = 2): Promise<pg.QueryResult> {
  if (Date.now() - lastConnFailureAt < OFFLINE_COOLDOWN_MS) {
    throw new Error('PostgreSQL connection temporarily unavailable (fast-fail circuit breaker)');
  }
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const res = await pool.query(text, params);
      lastConnFailureAt = 0;
      return res;
    } catch (err: unknown) {
      const pgCode =
        err && typeof err === 'object' && 'code' in err && typeof err.code === 'string'
          ? err.code
          : '';
      // Jangan retry atau sleep 600ms jika error adalah SQL schema/constraint (42xxx, 23xxx, 22xxx)
      if (/^(42|23|22)/.test(pgCode)) {
        throw err;
      }
      // Jika koneksi ditolak (offline DB di CI), aktifkan fast-fail circuit breaker
      if (pgCode === 'ECONNREFUSED' || pgCode === 'ENOTFOUND' || String(err).includes('ECONNREFUSED')) {
        lastConnFailureAt = Date.now();
        throw err;
      }
      if (attempt === retries) throw err;
      await setTimeout(200 * (attempt + 1));
    }
  }
  throw new Error('Query failed after retries');
}
