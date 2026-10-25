export interface WhatsAppNotificationPayload {
  toPhone: string;
  customerName: string;
  tenantName: string;
  ticketNumber: string;
  type: 'booking_confirmed' | 'next_in_line' | 'called';
  barberName?: string;
  chairNumber?: number;
  estMinutes?: number;
}

export interface DispatchedNotification {
  id: string;
  phone: string;
  message: string;
  dispatchedAt: string;
  status: 'sent' | 'queued';
}

export const notificationOutbox: DispatchedNotification[] = [];

export class NotificationService {
  /**
   * Menyusun pesan teks WhatsApp yang sopan, padat, dan jelas untuk pelanggan lokal
   */
  static formatMessage(payload: WhatsAppNotificationPayload): string {
    const { customerName, tenantName, ticketNumber, type, barberName, chairNumber, estMinutes } = payload;

    switch (type) {
      case 'booking_confirmed':
        return `Halo Kak ${customerName}, antrean Anda di *${tenantName}* berhasil terdaftar!\n\n` +
               `📌 *Nomor Tiket:* ${ticketNumber}\n` +
               `💈 *Kapster:* ${barberName || 'Sistem Smart Dispatch'}\n` +
               `⏱ *Estimasi Durasi:* ~${estMinutes || 25} Menit\n\n` +
               `Mohon hadir 10 menit sebelum giliran. Pantau nomor antrean Anda di aplikasi. Terima kasih!`;

      case 'next_in_line':
        return `⚠️ *PENGINGAT ANTREAN* - *${tenantName}*\n\n` +
               `Halo Kak ${customerName}, antrean Anda (*${ticketNumber}*) tinggal *1 orang lagi*!\n` +
               `Silakan bersiap dan segera merapat ke lokasi ruko agar kursi tidak terlewat. Terima kasih.`;

      case 'called':
        return `🔔 *GILIRAN TIBA* - *${tenantName}*\n\n` +
               `Panggilan untuk tiket *${ticketNumber}* (Kak ${customerName}):\n` +
               `Kursi potong *Nomor ${chairNumber || 1}* bersama *Kapster ${barberName || 'Bertugas'}* sudah siap.\n` +
               `Silakan langsung menempati kursi pangkas.`;
    }
  }

  /**
   * Mengirim notifikasi ke gateway (Baileys / WhatsApp Webhook) atau antrean outbox lokal
   */
  static async sendWhatsAppAlert(payload: WhatsAppNotificationPayload): Promise<DispatchedNotification> {
    const message = this.formatMessage(payload);
    const notification: DispatchedNotification = {
      id: `wa-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      phone: payload.toPhone,
      message,
      dispatchedAt: new Date().toISOString(),
      status: 'sent',
    };

    notificationOutbox.push(notification);
    if (notificationOutbox.length > 50) {
      notificationOutbox.splice(0, notificationOutbox.length - 50);
    }

    return notification;
  }
}
