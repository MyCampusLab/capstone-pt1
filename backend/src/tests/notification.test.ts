import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { NotificationService, notificationOutbox, type WhatsAppNotificationPayload } from '../services/notification.service.js';

describe('📲 Pengujian Notifikasi WhatsApp Otomatis (Kebiasaan Pelanggan Indonesia)', () => {
  test('Kasus 1: Notifikasi konfirmasi booking memuat nomor tiket, nama kapster, dan estimasi durasi', () => {
    const payload: WhatsAppNotificationPayload = {
      toPhone: '085727566125',
      customerName: 'Bagus Prakoso',
      tenantName: 'Stupid Culture Barbershop',
      ticketNumber: 'S-01',
      type: 'booking_confirmed',
      barberName: 'Bagas',
      estMinutes: 20,
    };

    const msg = NotificationService.formatMessage(payload);
    assert.ok(msg.includes('Stupid Culture Barbershop'));
    assert.ok(msg.includes('S-01'));
    assert.ok(msg.includes('Bagas'));
    assert.ok(msg.includes('~20 Menit'));
  });

  test('Kasus 2: Notifikasi pengingat tinggal 1 orang lagi (next_in_line) memuat peringatan segera merapat', () => {
    const payload: WhatsAppNotificationPayload = {
      toPhone: '081234567890',
      customerName: 'Rian Prasetyo',
      tenantName: 'Febrian Barbershop',
      ticketNumber: 'S-02',
      type: 'next_in_line',
    };

    const msg = NotificationService.formatMessage(payload);
    assert.ok(msg.includes('PENGINGAT ANTREAN'));
    assert.ok(msg.includes('tinggal *1 orang lagi*'));
    assert.ok(msg.includes('S-02'));
  });

  test('Kasus 3: Pengiriman alert ke outbox mencatat riwayat notifikasi dengan id unik', async () => {
    notificationOutbox.length = 0; // reset outbox

    const res = await NotificationService.sendWhatsAppAlert({
      toPhone: '081987654321',
      customerName: 'Dimas Aditya',
      tenantName: 'RR Barber Studio',
      ticketNumber: 'A-01',
      type: 'called',
      barberName: 'Kapster 1',
      chairNumber: 1,
    });

    assert.ok(res.id.startsWith('wa-'));
    assert.strictEqual(res.phone, '081987654321');
    assert.strictEqual(res.status, 'sent');
    assert.strictEqual(notificationOutbox.length, 1);
  });
});
