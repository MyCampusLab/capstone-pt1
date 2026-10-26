// lib/main_partner.dart
// Entrypoint APK Mitra / Kasir / Kapster (SmartBarber B2B - Kasir & Operasional Kursi)
import 'package:geges_smartbarber/main.dart';
import 'package:geges_smartbarber/screens/admin/partner_gate.dart';

void main() {
  bootstrapApp(
    appTitle: 'SmartBarber Partner - Kasir & Kapster',
    home: const PartnerGate(),
  );
}
