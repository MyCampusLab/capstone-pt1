import 'package:flutter/foundation.dart';
import 'email_outbox_service.dart';

class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  final EmailOutboxService _outbox = EmailOutboxService();

  /// Mengirim Email Sambutan via Outbox Queue (12-Factor III: Zero hardcoded credentials)
  Future<void> sendWelcomeEmail(String name, String email) async {
    try {
      await _outbox.queueEmail(
        to: email,
        subject: 'Selamat Datang di Geges Smart Barber!',
        body: 'Halo $name, terima kasih telah bergabung.',
        metadata: {'type': 'welcome', 'recipient_name': name},
      );
    } catch (e) {
      debugPrint('[EmailService] Gagal antrekan welcome email: $e');
    }
  }

  /// Mengirim Email Konfirmasi Pendaftaran Tenant via Outbox Queue
  Future<void> sendTenantRegistrationEmail(String shopName, String ownerEmail) async {
    try {
      await _outbox.queueEmail(
        to: ownerEmail,
        subject: 'Pendaftaran Diterima: $shopName',
        body: 'Pendaftaran kemitraan $shopName sedang diproses.',
        metadata: {'type': 'tenant_registration', 'shop_name': shopName},
      );
    } catch (e) {
      debugPrint('[EmailService] Gagal antrekan tenant registration email: $e');
    }
  }
}
