import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { FuzzySugenoQueueEstimator } from '../algorithms/fuzzySugeno.js';
import { SmartDispatchEngine, type ActiveBarber, type ActiveQueueItem } from '../algorithms/smartDispatch.js';

describe('🔬 Pengujian Algoritma Skripsi: Fuzzy Sugeno Orde-Nol', () => {
  test('Kasus 1: Layanan Ringan dengan Kapster Cepat menghasilkan durasi rendah (15-20m)', () => {
    const res = FuzzySugenoQueueEstimator.calculateDuration(2.0, 18.0);
    assert.strictEqual(res.roundedDuration, 15);
    assert.ok(res.crispDuration >= 15 && res.crispDuration <= 20);
  });

  test('Kasus 2: Layanan Sedang (Fade) dengan Kapster Standar menghasilkan ~35 menit', () => {
    const res = FuzzySugenoQueueEstimator.calculateDuration(5.5, 30.0);
    assert.strictEqual(res.roundedDuration, 35);
  });

  test('Kasus 3: Layanan Tinggi (Coloring) dengan Kapster Teliti menghasilkan ~65 menit', () => {
    const res = FuzzySugenoQueueEstimator.calculateDuration(8.5, 42.0);
    assert.strictEqual(res.roundedDuration, 65);
  });

  test('Kasus 4: Titik Transisi / Interpolasi Fuzzy (Kerumitan 4.0, Kapster 25m)', () => {
    const res = FuzzySugenoQueueEstimator.calculateDuration(4.0, 25.0);
    assert.ok(res.crispDuration > 15 && res.crispDuration < 45);
    assert.strictEqual(typeof res.roundedDuration, 'number');
  });
});

describe('⚖️ Pengujian Algoritma Skripsi: Smart Dispatch Heuristic (Workload Balancing)', () => {
  const barbers: ActiveBarber[] = [
    { id: 1, name: 'Ferdi', chair_number: 1, speed_val: 20 },
    { id: 2, name: 'Febri', chair_number: 2, speed_val: 30 },
    { id: 3, name: 'Hakim', chair_number: 3, speed_val: 40 },
  ];

  test('Kasus 1: Semua kapster kosong, alokasi diarahkan ke Kursi 1 (Tie-breaking)', () => {
    const queues: ActiveQueueItem[] = [];
    const res = SmartDispatchEngine.allocateQueue(barbers, queues, 30);
    assert.strictEqual(res.assignedBarber.id, 1);
    assert.strictEqual(res.queueStartWaitMinutes, 0);
  });

  test('Kasus 2: Ferdi sibuk (40m), Febri sibuk (20m), Hakim kosong (0m) -> Alokasi otomatis ke Hakim', () => {
    const now = new Date();
    const queues: ActiveQueueItem[] = [
      { id: 101, barber_id: 1, status: 'in_service', estimated_duration: 40, estimated_start_time: now.toISOString() },
      { id: 102, barber_id: 2, status: 'in_service', estimated_duration: 20, estimated_start_time: now.toISOString() },
    ];

    const res = SmartDispatchEngine.allocateQueue(barbers, queues, 25, 5, now);
    assert.strictEqual(res.assignedBarber.id, 3);
    assert.strictEqual(res.queueStartWaitMinutes, 0);
  });

  test('Kasus 3: Semua kapster memiliki antrean, alokasi memilih yang tercepat selesai', () => {
    const now = new Date();
    const queues: ActiveQueueItem[] = [
      { id: 101, barber_id: 1, status: 'in_service', estimated_duration: 50, estimated_start_time: now.toISOString() },
      { id: 102, barber_id: 2, status: 'in_service', estimated_duration: 15, estimated_start_time: now.toISOString() },
      { id: 103, barber_id: 3, status: 'in_service', estimated_duration: 60, estimated_start_time: now.toISOString() },
    ];

    const res = SmartDispatchEngine.allocateQueue(barbers, queues, 20, 5, now);
    assert.strictEqual(res.assignedBarber.id, 2);
    assert.strictEqual(res.assignedBarber.name, 'Febri');
  });
});
