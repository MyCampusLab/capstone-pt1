// lib/main_customer.dart
// Entrypoint APK Pelanggan (SmartBarber B2C - Reservasi & Antrean Cerdas)
import 'package:geges_smartbarber/main.dart';
import 'package:geges_smartbarber/screens/intro/splash_screen.dart';

void main() {
  bootstrapApp(
    appTitle: 'SmartBarber - Antrean & Reservasi',
    home: const SplashScreen(),
  );
}
