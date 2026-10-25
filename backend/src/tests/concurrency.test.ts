import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { SmartDispatchEngine, type ActiveBarber, type ActiveQueueItem } from '../algorithms/smartDispatch.js';

describe('⚡ Pengujian Konkurensi & Anti-Race Condition Antrean', () => {
  const barbers: ActiveBarber[] = [
    { id: 1, name: 'Bagas', chair_number: 1, speed_val: 20 },
    { id: 2, name: 'Reno', chair_number: 2, speed_val: 30 },
    { id: 3, name: 'Danang', chair_number: 3, speed_val: 35 },
  ];

  test('10 Permintaan Booking Masuk Bersamaan: Terdistribusi merata ke 3 kapster tanpa penumpukan tunggal', () => {
    const queueLog: ActiveQueueItem[] = [];
    const now = new Date();

    // Simulasikan 10 booking berurutan/bersamaan
    for (let i = 1; i <= 10; i++) {
      const dispatch = SmartDispatchEngine.allocateQueue(
        barbers,
        queueLog,
        25, // rata-rata durasi 25 menit
        5,  // buffer 5 menit
        now
      );

      queueLog.push({
        id: i,
        barber_id: dispatch.assignedBarber.id,
        status: 'waiting',
        estimated_duration: 25,
        estimated_start_time: dispatch.estimatedStartTime,
      });
    }

    assert.strictEqual(queueLog.length, 10);

    // Hitung distribusi kapster
    const countBagas = queueLog.filter((q) => q.barber_id === 1).length;
    const countReno = queueLog.filter((q) => q.barber_id === 2).length;
    const countDanang = queueLog.filter((q) => q.barber_id === 3).length;

    // Pastikan semua kapster mendapatkan antrean (tidak ada yang 0 dan tidak ada yang 10 sendirian)
    assert.ok(countBagas >= 2, `Bagas harus melayani minimal 2 pelanggan, dapat: ${countBagas}`);
    assert.ok(countReno >= 2, `Reno harus melayani minimal 2 pelanggan, dapat: ${countReno}`);
    assert.ok(countDanang >= 2, `Danang harus melayani minimal 2 pelanggan, dapat: ${countDanang}`);

    // Pastikan total antrean tepat 10
    assert.strictEqual(countBagas + countReno + countDanang, 10);
  });
});
