// lib/screens/admin/payment_verification_screen_improved.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:geges_smartbarber/services/booking_anti_duplicate_service.dart';
import 'package:geges_smartbarber/widgets/app_image.dart';

class PaymentVerificationScreenImproved extends StatefulWidget {
  final String? barbershopId;
  const PaymentVerificationScreenImproved({super.key, this.barbershopId});
  @override
  State<PaymentVerificationScreenImproved> createState() => _PaymentVerificationScreenImprovedState();
}

class _PaymentVerificationScreenImprovedState extends State<PaymentVerificationScreenImproved> {
  final BookingAntiDuplicateService _antiDupService = BookingAntiDuplicateService();

  Future<void> _refresh() async {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Verifikasi Pembayaran', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Segarkan data verifikasi',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          )
        ],
      ),
      body: StreamBuilder<List<DocumentSnapshot>>(
        stream: _antiDupService.streamPaymentVerificationQueue(barbershopId: widget.barbershopId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          
          final list = snapshot.data ?? [];
          if (list.isEmpty) return _buildEmpty();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, i) => _buildCard(list[i]),
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
      Icon(Icons.check_circle_outline, size: 64, color: Colors.white24),
      SizedBox(height: 16),
      Text('Semua pembayaran sudah diverifikasi', style: TextStyle(color: Colors.white54)),
    ]));
  }

  Widget _buildCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final payment = Map<String, dynamic>.from(data['payment'] ?? {});
    final proof = payment['proofUrl'] ?? data['payment_proof_base64'];
    final time = (payment['proofUploadedAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('ORDER #${doc.id.substring(0,6).toUpperCase()}', style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
            if (time != null) Text(DateFormat('HH:mm').format(time), style: const TextStyle(color: Colors.white24, fontSize: 12)),
          ]),
          const SizedBox(height: 12),
          Text(data['customer_name'] ?? 'Pelanggan', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Total: Rp ${data['total_price']}', style: const TextStyle(color: Color(0xFFC3A47B), fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          
          // Image Preview
          if (proof != null) 
            GestureDetector(
              onTap: () => _showFullImage(proof),
              child: AppImage(
                imageUrl: proof,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => _handleReject(doc.id),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
              child: const Text('TOLAK'),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: () => _handleAccept(doc.id),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.black),
              child: const Text('SETUJUI'),
            )),
          ]),
        ],
      ),
    );
  }

  void _showFullImage(String proof) {
    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: InteractiveViewer(child: AppImage(imageUrl: proof, fit: BoxFit.contain)),
    ));
  }

  Future<void> _handleAccept(String id) async {
    final admin = FirebaseAuth.instance.currentUser;
    await _antiDupService.acceptPaymentVerification(bookingId: id, adminUid: admin?.uid ?? 'admin');
    _showSnack('Pembayaran Disetujui');
  }

  Future<void> _handleReject(String id) async {
    final admin = FirebaseAuth.instance.currentUser;
    await _antiDupService.rejectPaymentVerification(bookingId: id, adminUid: admin?.uid ?? 'admin', rejectionReason: 'Bukti tidak sesuai');
    _showSnack('Pembayaran Ditolak', isError: true);
  }

  void _showSnack(String m, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: isError ? Colors.red : Colors.green));
  }
}