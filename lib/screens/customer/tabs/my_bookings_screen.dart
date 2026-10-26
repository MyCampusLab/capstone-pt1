// lib/screens/customer/tabs/my_bookings_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geges_smartbarber/config/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:geges_smartbarber/models/queue.dart';
import 'package:geges_smartbarber/services/queue_service.dart';
import 'package:geges_smartbarber/screens/customer/special_orders_screen.dart';
import 'package:geges_smartbarber/l10n/generated/app_localizations.dart';
import '../booking_detail_screen.dart';

const Color kBrownAccent = AppColors.primary;
const Color kDarkGrey = AppColors.surface;
const Color kSurface = AppColors.background;
const Color kTextGrey = AppColors.textSecondary;

class MyBookingsScreen extends StatefulWidget {
  final FirebaseFirestore? firestore;
  final QueueService? queueService;
  final String? currentUserId;

  const MyBookingsScreen({
    super.key,
    this.firestore,
    this.queueService,
    this.currentUserId,
  });

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  QueueService get _queueService =>
      widget.queueService ?? QueueService(firestore: widget.firestore);
  String? get _customerId =>
      widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
  FirebaseFirestore get _firestore =>
      widget.firestore ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_customerId != null) {
        _queueService.cancelExpiredWaitingQueuesForCustomer(_customerId!);
        _queueService.cancelExpiredAwaitingPaymentQueuesForCustomer(_customerId!);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(l10n.myOrders, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => SpecialOrdersScreen(firestore: _firestore, currentUserId: _customerId)));
            },
            icon: const Icon(Icons.stars, color: kBrownAccent),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: kBrownAccent,
          labelColor: kBrownAccent,
          unselectedLabelColor: kTextGrey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: [
            Tab(text: l10n.tabUnpaid), 
            Tab(text: l10n.tabScheduled),   
            Tab(text: l10n.tabProcessing),
            Tab(text: l10n.tabCompleted),
            Tab(text: l10n.tabCancelled),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Belum Bayar (Termasuk yang Menunggu Verifikasi)
          _BookingTabContent(
            statuses: const ['awaiting_payment', 'waiting'],
            filterPaid: null, // Show all (unpaid & waiting verification)
            services: _ServiceBundle(firestore: _firestore, queueService: _queueService),
            customerId: _customerId,
          ),
          // 2. Terjadwal (Sudah Diverifikasi / Booked)
          _BookingTabContent(
            statuses: const ['booked', 'cancellationRequested', 'cancellation_requested'],
            filterPaid: null, 
            services: _ServiceBundle(firestore: _firestore, queueService: _queueService),
            customerId: _customerId,
          ),
          _BookingTabContent(statuses: const ['ongoing'], services: _ServiceBundle(firestore: _firestore, queueService: _queueService), customerId: _customerId),
          _BookingTabContent(statuses: const ['served'], services: _ServiceBundle(firestore: _firestore, queueService: _queueService), customerId: _customerId),
          _BookingTabContent(statuses: const ['cancelled', 'refund_completed'], services: _ServiceBundle(firestore: _firestore, queueService: _queueService), customerId: _customerId),
        ],
      ),
    );
  }
}

class _ServiceBundle {
  final FirebaseFirestore firestore;
  final QueueService queueService;
  _ServiceBundle({required this.firestore, required this.queueService});
}

class _BookingTabContent extends StatefulWidget {
  final List<String> statuses;
  final bool? filterPaid; // Not used anymore for splitting tabs, but kept for compatibility if needed
  final _ServiceBundle services;
  final String? customerId;

  const _BookingTabContent({required this.statuses, this.filterPaid, required this.services, required this.customerId});

  @override
  State<_BookingTabContent> createState() => _BookingTabContentState();
}

class _BookingTabContentState extends State<_BookingTabContent> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    if (widget.customerId == null) return Center(child: Text(l10n.loginRequired));

    return StreamBuilder<List<Queue>>(
      stream: widget.services.queueService.streamQueuesForCustomer(widget.customerId!, statusFilter: widget.statuses),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: kBrownAccent));
        
        var list = snapshot.data ?? [];
        list.sort((a, b) => b.bookingTime.compareTo(a.bookingTime));

        if (list.isEmpty) return Center(child: Text(l10n.noOrders, style: const TextStyle(color: kTextGrey)));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, index) => _BookingCard(queue: list[index], firestore: widget.services.firestore),
        );
      },
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Queue queue;
  final FirebaseFirestore firestore;
  const _BookingCard({required this.queue, required this.firestore});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool hasPaid = (queue.paymentProofBase64 != null && queue.paymentProofBase64!.isNotEmpty) ||
                         (queue.paymentProofUrl != null && queue.paymentProofUrl!.isNotEmpty);
    
    // Status Logic
    String label = l10n.statusUnpaid;
    Color color = Colors.orange;

    if (queue.status == QueueStatus.cancelled || queue.status.value == 'cancelled') {
      label = l10n.statusCancelled; color = Colors.red;
    } else if (queue.status == QueueStatus.cancellationRequested || queue.status.value == 'cancellation_requested') {
      label = l10n.statusCancelRequested; color = Colors.orange;
    } else if (queue.status == QueueStatus.served || queue.status.value == 'served') {
      label = l10n.statusCompleted; color = Colors.green;
    } else if (queue.status == QueueStatus.ongoing || queue.status.value == 'ongoing') {
      label = l10n.statusProcessing; color = Colors.blue;
    } else if (queue.status == QueueStatus.booked || queue.status.value == 'booked') {
      label = l10n.statusScheduled; color = Colors.green;
    } else if (hasPaid) {
      // If none of the above (so likely 'waiting' or 'awaiting_payment') AND has paid:
      label = l10n.statusPendingVerification; color = Colors.amber;
    } else {
      // Default fallback
      label = l10n.statusUnpaid; color = Colors.orange;
    }

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailScreen(queueId: queue.id))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kDarkGrey, 
          borderRadius: BorderRadius.circular(12), 
          border: Border.all(color: color.withValues(alpha: 0.3))
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Booking #${queue.id.substring(0,5).toUpperCase()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(DateFormat('dd MMM, HH:mm').format(queue.bookingTime.toDate()), style: const TextStyle(color: kTextGrey, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
