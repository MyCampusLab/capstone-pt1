import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { query, pool } from './db.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export async function runMigrations(): Promise<void> {
  console.log('🔄 Menjalankan migrasi skema PostgreSQL...');
  const schemaPath = path.join(__dirname, 'schema.sql');
  const schemaSql = fs.readFileSync(schemaPath, 'utf-8');

  await query(schemaSql);
  console.log('✅ Migrasi skema database berhasil dieksekusi.');
}

if (process.argv[1]?.endsWith('migrate.ts')) {
  runMigrations()
    .then(() => pool.end())
    .catch((err: unknown) => {
      console.error('❌ Migrasi gagal:', err);
      process.exit(1);
    });
}
