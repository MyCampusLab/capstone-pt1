// lib/screens/admin/partner_gate.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geges_smartbarber/config/app_colors.dart';
import 'package:geges_smartbarber/services/auth_service.dart';
import 'package:geges_smartbarber/screens/admin/admin_dashboard.dart';
import 'package:geges_smartbarber/screens/auth/login_screen.dart';

class PartnerGate extends StatefulWidget {
  const PartnerGate({super.key});

  @override
  State<PartnerGate> createState() => _PartnerGateState();
}

class _PartnerGateState extends State<PartnerGate> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkPartnerAuth();
  }

  Future<void> _checkPartnerAuth() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => LoginScreen(
              adminBuilder: (_) => const AdminDashboardScreen(),
            ),
          ),
        );
        return;
      }

      final userData = await _authService.getUserById(user.uid);
      if (!mounted) return;

      if (userData == null) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }

      if (userData.isSuspended) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Akun mitra dinonaktifkan. Hubungi super admin.'),
            backgroundColor: AppColors.danger,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }

      final role = userData.role;
      final isPartner = role == 'admin_owner' ||
          role == 'owner' ||
          role == 'admin' ||
          role == 'super_admin' ||
          role == 'barberman' ||
          role == 'barber' ||
          role == 'cashier';

      if (isPartner) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
      } else {
        // Akun adalah customer biasa
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Akses Ditolak: Akun Anda (${userData.name}) terdaftar sebagai Pelanggan.\n\nAplikasi SmartBarber Partner ini khusus untuk Kasir, Kapster, dan Pemilik Barbershop.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Gagal memeriksa sesi mitra: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'SMARTBARBER PARTNER',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Memverifikasi Akses Kasir & Kapster...',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.admin_panel_settings_outlined, color: AppColors.danger, size: 64),
              const SizedBox(height: 20),
              const Text(
                'Akses Dibatasi',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Keluar & Ganti Akun Mitra', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
