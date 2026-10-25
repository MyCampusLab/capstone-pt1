// lib/screens/admin/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import 'package:geges_smartbarber/models/queue.dart';
import 'package:geges_smartbarber/services/queue_service.dart';
import 'package:geges_smartbarber/services/barbershop_service.dart';
import 'package:geges_smartbarber/services/auth_service.dart';
import 'package:geges_smartbarber/screens/auth/login_screen.dart';
import 'package:geges_smartbarber/screens/admin/live_queue_screen.dart';
import 'package:geges_smartbarber/screens/admin/_manual_booking_form.dart';
import 'package:geges_smartbarber/screens/admin/payment_verification_screen_improved.dart';
import 'package:geges_smartbarber/screens/admin/service_management_screen.dart';
import 'package:geges_smartbarber/screens/admin/barber_management_screen.dart';
import 'package:geges_smartbarber/screens/admin/cancellation_requests_screen.dart';
import 'package:geges_smartbarber/screens/admin/barbershop_settings_screen.dart';
import 'package:geges_smartbarber/screens/admin/barbershop_gallery_screen.dart';
import 'package:geges_smartbarber/screens/admin/account_management_screen.dart';
import 'package:geges_smartbarber/screens/admin/sales_report_screen.dart';
import 'package:geges_smartbarber/screens/admin/admin_dashboard_skeleton.dart';

const Color kBrownAccent = Color(0xFFC3A47B);
const Color kDarkSurface = Color(0xFF1E1E1E);
const Color kBlack = Colors.black;
const Color kRedNotification = Color(0xFFFF3B30);

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final QueueService _queueService = QueueService();
  final BarbershopService _barbershopService = BarbershopService();
  final AuthService _authService = AuthService();

  final String? _adminUid = FirebaseAuth.instance.currentUser?.uid;
  String? _adminBarbershopId;
  String _barbershopName = "Loading...";
  String _loadingError = '';
  bool _isLoading = true;
  bool _isShopOpen = false;
  bool _isTogglingStatus = false;

  @override
  void initState() {
    super.initState();
    _loadAdminData();
    // Expiration cancellation handled server-side (12-Factor backend)
  }

  @override
  void dispose() { super.dispose(); }

  Future<void> _loadAdminData() async {
    if (_adminUid == null) { _logout(context); return; }
    try {
      final adminData = await _authService.getUserById(_adminUid);
      if (adminData == null) { 
        if (mounted) setState(() { _loadingError = 'ERROR: Admin tidak ditemukan.'; _isLoading = false; }); 
        return; 
      }
      final barbershopId = adminData.barbershopId;
      if (barbershopId == null || barbershopId.isEmpty) { 
        if (mounted) setState(() { _adminBarbershopId = null; _isLoading = false; }); 
        return; 
      }
      final barbershop = await _barbershopService.getBarbershopById(barbershopId);
      if (mounted) {
        setState(() {
          _adminBarbershopId = barbershopId;
          _barbershopName = barbershop?.name ?? 'Barbershop Unknown';
          _isShopOpen = barbershop?.isOpen ?? false;
          _loadingError = '';
          _isLoading = false;
        });
      }
    } catch (e) { if (mounted) setState(() { _loadingError = 'FATAL ERROR: $e'; _isLoading = false; }); }
  }

  void _logout(BuildContext context) async {
    await _authService.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginScreen()), (Route<dynamic> route) => false);
  }

  // Helper: Find next relevant appointment
  Queue? _getNextAppointment(List<Queue> queues) {
    final now = DateTime.now();
    final active = queues.where((q) => q.status == QueueStatus.booked || q.status == QueueStatus.ongoing).toList();
    
    final todayUpcoming = active.where((q) { 
      final d = q.bookingTime.toDate(); 
      return d.year == now.year && d.month == now.month && d.day == now.day && d.isAfter(now.subtract(const Duration(minutes: 30))); 
    }).toList();
    
    todayUpcoming.sort((a, b) => a.bookingTime.toDate().compareTo(b.bookingTime.toDate()));
    if (todayUpcoming.isNotEmpty) return todayUpcoming.first;

    final futureUpcoming = active.where((q) => q.bookingTime.toDate().isAfter(now)).toList();
    futureUpcoming.sort((a, b) => a.bookingTime.toDate().compareTo(b.bookingTime.toDate()));
    if (futureUpcoming.isNotEmpty) return futureUpcoming.first;

    return null;
  }

  // Optimized Calculation for ALL time data
  Map<String, dynamic> _calculateEnhancedStats(List<Queue> queues) {
    int pendingPayment = 0;
    int verifyPayment = 0;
    int cancellationReq = 0;
    int totalBooked = 0;
    int totalOngoing = 0;
    int totalServed = 0;
    int totalCancelled = 0;

    for (var q in queues) {
      // Global Actionable Counts
      if (q.status == QueueStatus.awaitingPayment) {
        if (q.paymentProofBase64 == null || q.paymentProofBase64!.isEmpty) {
          pendingPayment++;
        } else {
          verifyPayment++;
        }
      } else if (q.status == QueueStatus.cancellationRequested) {
        cancellationReq++;
      }

      // Track all statuses across all days
      switch (q.status) {
        case QueueStatus.booked: totalBooked++; break;
        case QueueStatus.ongoing: totalOngoing++; break;
        case QueueStatus.served: totalServed++; break;
        case QueueStatus.cancelled: totalCancelled++; break;
        default: break;
      }
    }

    return {
      'stats': {
        'pending_payment': pendingPayment,
        'verify_payment': verifyPayment,
        'cancellation_req': cancellationReq,
        'today_booked': totalBooked, // Key remains for compatibility
        'today_ongoing': totalOngoing,
        'today_served': totalServed,
        'today_cancelled': totalCancelled,
      },
    };
  }

  Future<void> _toggleShopStatus() async {
    if (_adminBarbershopId == null || _isTogglingStatus) return;
    setState(() => _isTogglingStatus = true);
    try {
      await _barbershopService.updateShopStatus(_adminBarbershopId!, !_isShopOpen);
      if (mounted) {
        setState(() { _isShopOpen = !_isShopOpen; _isTogglingStatus = false; });
      }
    } catch (e) { if (mounted) setState(() => _isTogglingStatus = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingError.isNotEmpty) {
      return Scaffold(
        backgroundColor: kBlack,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_loadingError, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loadAdminData,
                style: ElevatedButton.styleFrom(backgroundColor: kBrownAccent),
                child: const Text('Coba Lagi', style: TextStyle(color: Colors.black)),
              )
            ],
          ),
        ),
      );
    }
    
    // 1. Show skeleton while fetching user data
    if (_isLoading) return const AdminDashboardSkeleton();

    // 2. Only show error screen if we ARE NOT loading AND still have no barbershopId
    if (_adminBarbershopId == null) {
       return Scaffold(
         backgroundColor: kBlack,
         appBar: AppBar(title: const Text("Admin Dashboard"), backgroundColor: kBlack),
         body: Center(
           child: Padding(
             padding: const EdgeInsets.all(24.0),
             child: Column(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 const Icon(Icons.store_mall_directory_outlined, size: 64, color: kBrownAccent),
                 const SizedBox(height: 24),
                 const Text(
                   "Akun Anda adalah Admin, namun belum memiliki Barbershop.",
                   textAlign: TextAlign.center,
                   style: TextStyle(color: Colors.white, fontSize: 16),
                 ),
                 const SizedBox(height: 12),
                 const Text(
                   "Silakan hubungi Super Admin untuk menghubungkan akun Anda dengan Barbershop.",
                   textAlign: TextAlign.center,
                   style: TextStyle(color: Colors.white54, fontSize: 14),
                 ),
                 const SizedBox(height: 32),
                 ElevatedButton(
                   onPressed: () => _logout(context),
                   style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                   child: const Text("Logout", style: TextStyle(color: Colors.white)),
                 )
               ],
             ),
           ),
         ),
       );
    }

    // Accuracy: Fetch ALL data for this barbershop to track all-time status
    final stream = _queueService.streamQueuesForBarbershop(
      _adminBarbershopId!, 
      statusFilter: ['waiting', 'awaiting_payment', 'booked', 'ongoing', 'served', 'cancelled', 'cancellation_requested'], 
      limit: 500 // Increased limit to capture broader history
    );

    return Scaffold(
      backgroundColor: kBlack,
      body: StreamBuilder<List<Queue>>(
        stream: stream,
        builder: (context, snapshot) {
          final isSyncing = snapshot.connectionState == ConnectionState.waiting;
          
          if (isSyncing && !snapshot.hasData) {
             return const AdminDashboardSkeleton();
          }
          
          final allQueues = snapshot.data ?? [];
          final dashboardData = _calculateEnhancedStats(allQueues);
          final nextQueue = _getNextAppointment(allQueues);

          return SafeArea(
            child: RefreshIndicator(
              onRefresh: () async => _loadAdminData(),
              color: kBrownAccent,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                children: [
                  _buildTopBar(isLive: snapshot.hasData),
                  const SizedBox(height: 24),
                  _buildShopToggle(),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Monitoring Antrean', 'Semua Data Ter-sinkronisasi'),
                  const SizedBox(height: 12),
                  _buildRealtimeStatsRow(dashboardData['stats'] as Map<String, int>),
                  const SizedBox(height: 28),
                  if (nextQueue != null) ...[
                    _buildSectionHeader('Antrean Aktif / Mendatang', 'Live Update'),
                    const SizedBox(height: 12),
                    _buildUpcomingAppointmentCard(nextQueue),
                    const SizedBox(height: 28),
                  ] else if (!isSyncing) ...[
                     _buildNoDataPrompt(),
                     const SizedBox(height: 28),
                  ],
                  _buildSectionHeader('Main Menu', 'Kelola Barbershop'),
                  const SizedBox(height: 16),
                  _buildGridMenu(dashboardData['stats'] as Map<String, int>),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(subtitle, style: TextStyle(color: kBrownAccent.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  Widget _buildNoDataPrompt() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kDarkSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05))
      ),
      child: const Center(
        child: Column(
          children: [
            Icon(Icons.event_busy, color: Colors.white24, size: 40),
            SizedBox(height: 12),
            Text('Tidak ada data antrean ditemukan', style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar({bool isLive = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_barbershopName.toUpperCase(), 
               style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.5),
               maxLines: 1, overflow: TextOverflow.ellipsis),
          Row(
            children: [
              const Text('Admin Control Panel', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w400)),
              if (isLive) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green.withValues(alpha: 0.3))),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sensors, color: Colors.green, size: 10),
                      SizedBox(width: 4),
                      Text('LIVE', style: TextStyle(color: Colors.green, fontSize: 8, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ]),
      ),
      _buildLogoutButton(),
    ]);
  }

  Widget _buildLogoutButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1), 
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2))
      ),
      child: IconButton(
        onPressed: () => _confirmLogout(), 
        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 24)
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kDarkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Konfirmasi Keluar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Apakah Anda yakin ingin keluar dari akun admin?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _logout(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
            ),
            child: const Text('Keluar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildShopToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), 
      decoration: BoxDecoration(
        color: kDarkSurface, 
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _isShopOpen ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1))
      ), 
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Container(
            width: 10, height: 10, 
            decoration: BoxDecoration(
              color: _isShopOpen ? Colors.green : Colors.red, 
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: (_isShopOpen ? Colors.green : Colors.red).withValues(alpha: 0.5), blurRadius: 8)]
            )
          ),
          const SizedBox(width: 12),
          Text(_isShopOpen ? 'OPERASIONAL BUKA' : 'OPERASIONAL TUTUP', 
               style: TextStyle(color: _isShopOpen ? Colors.green : Colors.red, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.5)),
        ]),
        Transform.scale(
          scale: 0.8,
          child: Switch(
            value: _isShopOpen, 
            onChanged: _isTogglingStatus ? null : (_) => _toggleShopStatus(), 
            activeThumbColor: Colors.green, 
            activeTrackColor: Colors.green.withValues(alpha: 0.2), 
            inactiveThumbColor: Colors.red, 
            inactiveTrackColor: Colors.red.withValues(alpha: 0.2)
          ),
        ),
      ]));
  }

  Widget _buildRealtimeStatsRow(Map<String, int> stats) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal, 
      physics: const BouncingScrollPhysics(),
      child: Row(children: [
        _statChip('Verify', stats['verify_payment']!, Colors.blueAccent), const SizedBox(width: 12),
        _statChip('Booked', stats['today_booked']!, kBrownAccent), const SizedBox(width: 12),
        _statChip('Active', stats['today_ongoing']!, Colors.greenAccent), const SizedBox(width: 12),
        _statChip('Unpaid', stats['pending_payment']!, Colors.amber), const SizedBox(width: 12),
        _statChip('Done', stats['today_served']!, Colors.grey), const SizedBox(width: 12),
        _statChip('Cancel', stats['today_cancelled']!, Colors.redAccent),
      ])
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 90),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), 
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05), 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5)
      ), 
      child: Column(children: [
        Text(count.toString(), style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
      ]));
  }

  Widget _buildGridMenu(Map<String, int> stats) {
    return GridView.count(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), children: [
      _menuItem(Icons.verified_user_outlined, 'Verifikasi Bayar', 'Pembayaran Masuk', () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentVerificationScreenImproved(barbershopId: _adminBarbershopId))), badge: stats['verify_payment']!),
      _menuItem(Icons.playlist_add_check, 'Live Queue', 'Antrean Hari Ini', () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiveQueueScreen(barbershopId: _adminBarbershopId!, initialFilter: ['booked', 'ongoing'], title: 'Antrean Live'))), badge: stats['today_booked']! + stats['today_ongoing']!),
      _menuItem(Icons.cancel_presentation, 'Request Batal', 'Pengajuan Refund', () => Navigator.push(context, MaterialPageRoute(builder: (_) => CancellationRequestsScreen(currentUserId: _adminUid))), badge: stats['cancellation_req']!),
      _menuItem(Icons.add_circle_outline, 'Booking Manual', 'Input Offline', _goToManualBooking),
      _menuItem(Icons.people_outline, 'Karyawan', 'Manage Staff', () => Navigator.push(context, MaterialPageRoute(builder: (_) => BarberManagementScreen(barbershopId: _adminBarbershopId!)))),
      _menuItem(Icons.cut_outlined, 'Layanan', 'Manage Service', () => Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceManagementScreen(barbershopId: _adminBarbershopId!)))),
      _menuItem(Icons.storefront, 'Profil Toko', 'Settings', () async {
        final shop = await _barbershopService.getBarbershopById(_adminBarbershopId!);
        if (shop != null && mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => BarbershopSettingsScreen(barbershop: shop)));
      }),
      _menuItem(Icons.photo_library, 'Galeri Album', 'Manage Photos', () async {
        final shop = await _barbershopService.getBarbershopById(_adminBarbershopId!);
        if (shop != null && mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => BarbershopGalleryScreen(barbershop: shop)));
      }),
      _menuItem(Icons.analytics_outlined, 'Laporan Penjualan', 'Revenue Report', () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalesReportScreen(barbershopId: _adminBarbershopId!)))),
      _menuItem(Icons.manage_accounts_outlined, 'Akun Saya', 'Edit Profile', () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountManagementScreen(userId: _adminUid!)))),
    ]);
  }

  Widget _menuItem(IconData icon, String title, String sub, VoidCallback onTap, {int badge = 0}) {
    return Stack(clipBehavior: Clip.none, children: [
      InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: kDarkSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: kBrownAccent, size: 28),
        const Spacer(),
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]))),
      if (badge > 0) Positioned(top: -5, right: -5, child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: kRedNotification, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))]), constraints: const BoxConstraints(minWidth: 24, minHeight: 24), child: Center(child: Text(badge > 99 ? '99+' : badge.toString(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))))),
    ]);
  }

  void _goToManualBooking() async {
    final barbershop = await _barbershopService.getBarbershopById(_adminBarbershopId!);
    if (barbershop != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Input Booking Offline'), backgroundColor: kBlack), backgroundColor: kBlack, body: ManualBookingForm(barbershop: barbershop, queueService: _queueService))));
    }
  }

  Widget _buildUpcomingAppointmentCard(Queue next) {
    final now = DateTime.now();
    final d = next.bookingTime.toDate();
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    
    return Container(
      padding: const EdgeInsets.all(16), 
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kBrownAccent.withValues(alpha: 0.2), kDarkSurface]
        ), 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: kBrownAccent.withValues(alpha: 0.3))
      ), 
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12), 
            decoration: BoxDecoration(color: kBrownAccent.withValues(alpha: 0.2), shape: BoxShape.circle), 
            child: const Icon(Icons.notifications_active, color: kBrownAccent)
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Text(
                  isToday ? "Jadwal Berikutnya (Hari Ini)" : "Jadwal Mendatang", 
                  style: const TextStyle(color: Colors.white54, fontSize: 12)
                ),
                const SizedBox(height: 4),
                Text(
                  isToday ? DateFormat('HH:mm').format(d) : DateFormat('dd MMM, HH:mm').format(d), 
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)
                ),
                Text(
                  next.status == QueueStatus.ongoing ? "Sedang Berlangsung" : "Siap Dilayani", 
                  style: TextStyle(
                    color: next.status == QueueStatus.ongoing ? Colors.green : Colors.blueAccent, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 12
                  )
                )
              ]
            )
          ),
        ]
      )
    );
  }
}
