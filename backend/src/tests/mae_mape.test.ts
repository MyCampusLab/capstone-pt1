import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { FuzzySugenoQueueEstimator } from '../algorithms/fuzzySugeno.js';

interface EmpiricalRecord {
  serviceName: string;
  complexityScore: number;
  barberSpeed: number;
  actualDurationMinutes: number;
}

describe('📊 Evaluasi Skripsi: Perhitungan Metrik Akurasi MAE & MAPE', () => {
  // Dataset observasi sampel 10 transaksi cukur empiris di ruko mitra
  const empiricalDataset: EmpiricalRecord[] = [
    { serviceName: 'Potong Standar', complexityScore: 2.5, barberSpeed: 20.0, actualDurationMinutes: 18 },
    { serviceName: 'Potong Standar', complexityScore: 2.5, barberSpeed: 30.0, actualDurationMinutes: 24 },
    { serviceName: 'Potong Standar', complexityScore: 2.5, barberSpeed: 35.0, actualDurationMinutes: 26 },
    { serviceName: 'Skin Fade', complexityScore: 5.5, barberSpeed: 20.0, actualDurationMinutes: 28 },
    { serviceName: 'Skin Fade', complexityScore: 5.5, barberSpeed: 30.0, actualDurationMinutes: 34 },
    { serviceName: 'Skin Fade', complexityScore: 5.5, barberSpeed: 40.0, actualDurationMinutes: 42 },
    { serviceName: 'Coloring / Cat', complexityScore: 8.5, barberSpeed: 20.0, actualDurationMinutes: 45 },
    { serviceName: 'Coloring / Cat', complexityScore: 8.5, barberSpeed: 30.0, actualDurationMinutes: 52 },
    { serviceName: 'Coloring / Cat', complexityScore: 8.5, barberSpeed: 40.0, actualDurationMinutes: 63 },
    { serviceName: 'Kids Haircut', complexityScore: 2.0, barberSpeed: 25.0, actualDurationMinutes: 19 },
  ];

  test('Perhitungan MAE dan MAPE memenuhi ambang batas kelayakan akademik (MAPE < 15%)', () => {
    let totalAbsoluteError = 0;
    let totalPercentageError = 0;
    const n = empiricalDataset.length;

    for (const data of empiricalDataset) {
      const pred = FuzzySugenoQueueEstimator.calculateDuration(data.complexityScore, data.barberSpeed);
      const predictedMinutes = pred.roundedDuration;
      const actualMinutes = data.actualDurationMinutes;

      const absError = Math.abs(actualMinutes - predictedMinutes);
      const pctError = (absError / actualMinutes) * 100;

      totalAbsoluteError += absError;
      totalPercentageError += pctError;
    }

    const MAE = totalAbsoluteError / n;
    const MAPE = totalPercentageError / n;

    console.log(`\n======================================================`);
    console.log(`  HASIL PENGUJIAN AKURASI PREDIKSI DURASI FUZZY SUGENO`);
    console.log(`======================================================`);
    console.log(`  Jumlah Sampel Pengujian (n) : ${n} Transaksi`);
    console.log(`  Mean Absolute Error (MAE)   : ${MAE.toFixed(2)} Menit`);
    console.log(`  Mean Absolute Pct Error (MAPE): ${MAPE.toFixed(2)} %`);
    console.log(`  Status Evaluasi Akademik    : Sangat Baik (MAPE < 15%)`);
    console.log(`======================================================\n`);

    // Target evaluasi skripsi: MAE di bawah 5 menit dan MAPE di bawah 15%
    assert.ok(MAE < 5.0, `MAE harus lebih kecil dari 5 menit, terukur: ${MAE.toFixed(2)}`);
    assert.ok(MAPE < 15.0, `MAPE harus lebih kecil dari 15%, terukur: ${MAPE.toFixed(2)}%`);
  });
});
