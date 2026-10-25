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

export async function query(text: string, params?: unknown[], retries = 2): Promise<pg.QueryResult> {
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      return await pool.query(text, params);
    } catch (err: unknown) {
      if (attempt === retries) throw err;
      await setTimeout(200 * (attempt + 1));
    }
  }
  throw new Error('Query failed after retries');
}
