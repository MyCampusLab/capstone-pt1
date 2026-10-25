// lib/screens/admin/cancellation_requests_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:geges_smartbarber/models/queue.dart';
import 'package:geges_smartbarber/services/queue_service.dart';

// --- THEME CONSTANTS ---
const Color kBrownAccent = Color(0xFFC3A47B);
const Color kDarkGrey = Color(0xFF1E1E1E);
const Color kSurface = Colors.black;
const Color kTextGrey = Colors.white70;
const Color kOrangeWarning = Color(0xFFFFB74D);
const Color kGreenSuccess = Color(0xFF81C784);
const Color kRedError = Color(0xFFE57373);

class CancellationRequestsScreen extends StatefulWidget {
  final String? currentUserId;
  const CancellationRequestsScreen({super.key, this.currentUserId});
  @override
  State<CancellationRequestsScreen> createState() =>
      _CancellationRequestsScreenState();
}

class _CancellationRequestsScreenState
    extends State<CancellationRequestsScreen> {
  final QueueService _queueService = QueueService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Simple memory cache
  final Map<String, String> _nameCache = {};
  
  Future<String> _getName(String collection, String id, String defaultVal) async {
    final key = '$collection-$id';
    if (_nameCache.containsKey(key)) return _nameCache[key]!;
    try {
      final doc = await _firestore.collection(collection).doc(id).get();
      final name = doc.data()?['name'] ?? defaultVal;
      _nameCache[key] = name;
      return name;
    } catch (_) {
      return defaultVal;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Permintaan Pembatalan',
          style: TextStyle(
            fontWeight: FontWeight.w900, 
            fontSize: 18, 
            letterSpacing: 0.5
          ),
        ),
      ),
      body: StreamBuilder<List<Queue>>(
        stream: _queueService.streamAllQueues(
          statusFilter: ['cancellation_requested'],
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: kBrownAccent));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: kRedError)));
          }
          
          final requests = snapshot.data ?? [];
          
          if (requests.isEmpty) {
            return _buildEmptyState();
          }
          
          // Sort: Newest requests first
          requests.sort((a, b) => b.bookingTime.compareTo(a.bookingTime));
          
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: requests.length,
            itemBuilder: (context, i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _CancellationCard(
                  queue: requests[i],
                  getName: _getName,
                  onTap: () => _showDetailModal(requests[i]),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: kDarkGrey,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white10),
            ),
            child: const Icon(Icons.assignment_turned_in_outlined, color: Colors.white24, size: 48),
          ),
          const SizedBox(height: 24),
          const Text('Semua Beres!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Tidak ada permintaan refund saat ini.', style: TextStyle(color: kTextGrey, fontSize: 14)),
        ],
      ),
    );
  }

  void _showDetailModal(Queue q) async {
    // Pre-fetch critical names before showing modal for snappier feel
    final customerName = await _getName('users', q.customerId, 'Customer');
    final shopName = await _getName('barbershops', q.barbershopId, 'Barbershop');
    
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // Transparent for custom styling
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: _CancellationDetailSheet(
          queue: q,
          customerName: customerName,
          shopName: shopName,
          queueService: _queueService,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
  }
}

/// A stable, stateful card that fetches and caches its own display data.
/// Prevents flickering and redundant re-fetches during scrolling.
class _CancellationCard extends StatefulWidget {
  final Queue queue;
  final Future<String> Function(String, String, String) getName;
  final VoidCallback onTap;

  const _CancellationCard({
    required this.queue,
    required this.getName,
    required this.onTap,
  });

  @override
  State<_CancellationCard> createState() => _CancellationCardState();
}

class _CancellationCardState extends State<_CancellationCard> with SingleTickerProviderStateMixin {
  String? _customerName;
  String? _shopName;
  String? _shopImage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final cName = await widget.getName('users', widget.queue.customerId, 'Customer');
      final sName = await widget.getName('barbershops', widget.queue.barbershopId, 'Barbershop');
      
      // Fetch image directly here
      String img = 'https://cdn-icons-png.flaticon.com/512/706/706830.png';
      try {
        final doc = await FirebaseFirestore.instance.collection('barbershops').doc(widget.queue.barbershopId).get();
        img = doc.data()?['imageUrl'] ?? img;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _customerName = cName;
          _shopName = sName;
          _shopImage = img;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final refundAmount = (widget.queue.totalPrice ?? 0) * 0.9;
    final reason = widget.queue.cancellationReason ?? 'Tidak ada alasan';

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: kDarkGrey,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            // Top Section: Image & Badge
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: _loading 
                      ? Container(color: Colors.white10)
                      : CachedNetworkImage(
                          imageUrl: _shopImage!,
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 300),
                        ),
                  ),
                ),
                Container(
                  height: 110,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: kOrangeWarning,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.priority_high_rounded, size: 12, color: Colors.black),
                        SizedBox(width: 4),
                        Text(
                          'BUTUH REFUND', 
                          style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 16,
                  right: 16,
                  child: _loading 
                    ? _buildShimmerBlock(width: 150, height: 16)
                    : Text(
                        _shopName ?? 'Barbershop',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                ),
              ],
            ),

            // Bottom Section: Details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer & Reason
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.person_pin_circle_outlined, color: kBrownAccent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _loading 
                              ? _buildShimmerBlock(width: 100, height: 12)
                              : Text(_customerName ?? 'Customer', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(
                              '"$reason"', 
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, fontStyle: FontStyle.italic),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                  
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(color: Colors.white10, height: 1),
                  ),

                  // Footer: Date & Price
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('dd MMM • HH:mm').format(widget.queue.bookingTime.toDate()),
                        style: const TextStyle(color: kTextGrey, fontSize: 12),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: kBrownAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: kBrownAccent.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          'Refund: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(refundAmount)}',
                          style: const TextStyle(color: kBrownAccent, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerBlock({required double width, required double height}) {
    return Container(
      width: width, height: height,
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
    );
  }
}

// --- DETAIL MODAL ---

class _CancellationDetailSheet extends StatefulWidget {
  final Queue queue;
  final String customerName;
  final String shopName;
  final QueueService queueService;
  final String? currentUserId;

  const _CancellationDetailSheet({
    required this.queue,
    required this.customerName,
    required this.shopName,
    required this.queueService,
    this.currentUserId,
  });

  @override
  State<_CancellationDetailSheet> createState() => _CancellationDetailSheetState();
}

class _CancellationDetailSheetState extends State<_CancellationDetailSheet> {
  bool _isLoading = false;
  final TextEditingController _adminNotesCtrl = TextEditingController();

  @override
  void dispose() {
    _adminNotesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final refundAmount = (widget.queue.totalPrice ?? 0) * 0.9;
    final reason = widget.queue.cancellationReason ?? 'Tidak ada alasan';

    return Container(
      decoration: const BoxDecoration(
        color: kDarkGrey,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Detail Refund', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      Text('Booking #${widget.queue.id.substring(0, 6).toUpperCase()}', style: const TextStyle(color: kTextGrey, fontSize: 13, letterSpacing: 1)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: kOrangeWarning.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.currency_exchange, color: kOrangeWarning),
                ),
              ],
            ),
          ),

          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Warning Box (Reason)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kOrangeWarning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kOrangeWarning.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.feedback_rounded, color: kOrangeWarning, size: 16),
                            SizedBox(width: 8),
                            Text('Alasan Customer', style: TextStyle(color: kOrangeWarning, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('"$reason"', style: const TextStyle(color: Colors.white, fontSize: 14, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Data Grid
                  _buildDataRow('Customer', widget.customerName),
                  _buildDataRow('Barbershop', widget.shopName),
                  _buildDataRow('Jadwal', DateFormat('EEEE, d MMM yyyy • HH:mm').format(widget.queue.bookingTime.toDate())),
                  
                  const SizedBox(height: 24),

                  const Text('Catatan Refund (Wajib)', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _adminNotesCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Misal: Refund disetujui, bukti transfer terlampir.',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    maxLines: 2,
                  ),

                  const SizedBox(height: 24),

                  // Refund Calculation Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      children: [
                        _buildMathRow('Biaya Layanan', widget.queue.totalPrice ?? 0),
                        _buildMathRow('Fee Admin / Penalty (10%)', -((widget.queue.totalPrice ?? 0) * 0.1).round(), isNegative: true),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(color: Colors.white10),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Transfer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            Text(
                              NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(refundAmount),
                              style: const TextStyle(color: kGreenSuccess, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                // Reject Button
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => _handleAction(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kRedError,
                      side: const BorderSide(color: kRedError),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('TOLAK', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                // Approve Button
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _handleAction(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreenSuccess,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Text('SETUJUI & UPLOAD', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: kTextGrey, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildMathRow(String label, int amount, {bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isNegative ? kRedError : kTextGrey, fontSize: 13)),
          Text(
            NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount),
            style: TextStyle(color: isNegative ? kRedError : Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(bool approve) async {
    if (approve && _adminNotesCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Harap isi catatan refund'), backgroundColor: kOrangeWarning));
      return;
    }

    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      if (approve) {
        final XFile? proof = await _pickProofImage();
        String? base64Proof;
        if (proof != null) {
           final bytes = await proof.readAsBytes();
           base64Proof = base64Encode(bytes);
        }

        await widget.queueService.adminProcessRefund(
          widget.queue.id,
          refundProofBase64: base64Proof ?? '', 
          adminUid: widget.currentUserId,
          adminNotes: _adminNotesCtrl.text.trim(),
        );
        messenger.showSnackBar(const SnackBar(content: Text('Refund berhasil diproses'), backgroundColor: kGreenSuccess));
      } else {
        await widget.queueService.adminRejectCancellation(widget.queue.id);
        messenger.showSnackBar(const SnackBar(content: Text('Permintaan refund ditolak'), backgroundColor: kRedError));
      }
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal: $e'), backgroundColor: kRedError));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<XFile?> _pickProofImage() async {
    final picker = ImagePicker();
    return await showModalBottomSheet<XFile?>(
      context: context,
      backgroundColor: kDarkGrey,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Upload Bukti Transfer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildMediaButton(c, Icons.photo_library_rounded, 'Galeri', () async {
                    final navigator = Navigator.of(c);
                    final f = await picker.pickImage(source: ImageSource.gallery, maxHeight: 800, maxWidth: 800, imageQuality: 80);
                    navigator.pop(f);
                  }),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMediaButton(c, Icons.camera_alt_rounded, 'Kamera', () async {
                    final navigator = Navigator.of(c);
                    final f = await picker.pickImage(source: ImageSource.camera, maxHeight: 800, maxWidth: 800, imageQuality: 80);
                    navigator.pop(f);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(c, null),
              child: const Text('Lanjutkan Tanpa Bukti', style: TextStyle(color: kTextGrey)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMediaButton(BuildContext c, IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(icon, color: kBrownAccent, size: 32),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}