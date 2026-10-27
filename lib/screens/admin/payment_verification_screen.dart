// lib/screens/admin/payment_verification_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:geges_smartbarber/models/queue.dart';
import 'package:geges_smartbarber/services/queue_service.dart';
import 'package:geges_smartbarber/widgets/app_image.dart';
import 'package:geges_smartbarber/services/http_api_client.dart';

const Color kBrownAccent = Color(0xFFC3A47B);
const Color kDarkGrey = Color(0xFF1E1E1E);
const Color kSurface = Colors.black;
const Color kTextGrey = Colors.white70;

class PaymentVerificationScreen extends StatefulWidget {
  const PaymentVerificationScreen({super.key});

  @override
  State<PaymentVerificationScreen> createState() =>
      _PaymentVerificationScreenState();
}

class _PaymentVerificationScreenState extends State<PaymentVerificationScreen> {
  final QueueService _queueService = QueueService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, String> _nameCache = {};
  
  bool _isLoadingDetails = false;
  final Map<String, Map<String, dynamic>> _detailsMap = {};
  List<Map<String, dynamic>> _unmatchedNotifications = [];

  @override
  void initState() {
    super.initState();
    _loadUnmatchedFromBackend();
  }

  Future<void> _loadUnmatchedFromBackend([Iterable<String>? extraSlugs]) async {
    final slugs = <String>{
      'febrian-barbershop',
      'rr-barber-studio',
      'stupid-culture',
      if (extraSlugs != null) ...extraSlugs.where((s) => s.isNotEmpty),
    };
    final collected = <Map<String, dynamic>>[];
    final api = HttpApiClient();
    try {
      for (final slug in slugs) {
        try {
          final res = await api.get('/api/payments/$slug/unmatched');
          if (res is List) {
            for (final item in res.whereType<Map>()) {
              final map = Map<String, dynamic>.from(item);
              map['tenant_slug'] ??= slug;
              collected.add(map);
            }
          }
        } catch (_) {}
      }
    } finally {
      api.close();
    }
    if (!mounted) return;
    setState(() {
      _unmatchedNotifications = collected;
    });
  }

  Future<void> _fetchBulkDetails(List<Queue> queues) async {
    final customerIds = queues.map((q) => q.customerId).toSet();
    final shopIds = queues.map((q) => q.barbershopId).toSet();
    final allServiceIds = queues.expand((q) => q.serviceIds ?? <String>[]).toSet();

    // Only fetch what's not in cache
    final customersToFetch = customerIds.where((id) => !_nameCache.containsKey('c_$id')).toList();
    final shopsToFetch = shopIds.where((id) => !_nameCache.containsKey('bs_$id')).toList();
    final servicesToFetch = allServiceIds.where((id) => !_nameCache.containsKey('s_$id')).toList();

    if (customersToFetch.isEmpty && shopsToFetch.isEmpty && servicesToFetch.isEmpty) {
      _updateDetailsMap(queues);
      return;
    }

    setState(() => _isLoadingDetails = true);

    try {
      // Parallel fetch
      await Future.wait([
        if (customersToFetch.isNotEmpty) _fetchDocs('users', customersToFetch, 'c_'),
        if (shopsToFetch.isNotEmpty) _fetchDocs('barbershops', shopsToFetch, 'bs_'),
        if (servicesToFetch.isNotEmpty) _fetchDocs('services', servicesToFetch, 's_'),
      ]);
      _updateDetailsMap(queues);
    } catch (e) {
      debugPrint('Error bulk fetching: $e');
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  Future<void> _fetchDocs(String collection, List<String> ids, String cachePrefix) async {
    // Firestore whereIn limit is 30 in some versions, but 10 is safer for older ones.
    // However, Future.wait with individual gets is often fast enough if parallelized.
    await Future.wait(ids.map((id) async {
      try {
        final doc = await _firestore.collection(collection).doc(id).get();
        _nameCache['$cachePrefix$id'] = doc.data()?['name'] ?? 'Unknown';
      } catch (_) {
        _nameCache['$cachePrefix$id'] = 'Unknown';
      }
    }));
  }

  void _updateDetailsMap(List<Queue> queues) {
    for (final q in queues) {
      final customer = _nameCache['c_${q.customerId}'] ?? 'Customer';
      final shop = _nameCache['bs_${q.barbershopId}'] ?? 'Barbershop';
      
      String serviceNames = 'Layanan';
      if (q.serviceIds != null && q.serviceIds!.isNotEmpty) {
        final names = q.serviceIds!
            .map((id) => _nameCache['s_$id'])
            .where((n) => n != null)
            .toList();
        if (names.isNotEmpty) {
          serviceNames = names.length == 1 ? names[0]! : '${names[0]} +${names.length - 1}';
        }
      }
      
      _detailsMap[q.id] = {
        'customer': customer,
        'shop': shop,
        'service': serviceNames,
      };
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
        title: const Text(
          'Verifikasi Pembayaran',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        actions: [
          IconButton(
            tooltip: 'Sinkronisasi Mutasi DompetKu',
            icon: const Icon(Icons.sync_rounded, color: kBrownAccent),
            onPressed: _loadUnmatchedFromBackend,
          ),
        ],
      ),
      body: StreamBuilder<List<Queue>>(
        stream: _queueService.streamAllQueues(
          statusFilter: ['awaiting_payment'],
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _detailsMap.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: kBrownAccent),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final requests = snapshot.data ?? [];
          if (requests.isEmpty && _unmatchedNotifications.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payment, color: kTextGrey, size: 60),
                  SizedBox(height: 16),
                  Text(
                    'Tidak ada pembayaran untuk diverifikasi',
                    style: TextStyle(color: kTextGrey),
                  ),
                ],
              ),
            );
          }

          // Trigger bulk fetch when data changes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            bool needsFetch = requests.any((q) => !_detailsMap.containsKey(q.id));
            if (needsFetch && !_isLoadingDetails) {
              _fetchBulkDetails(requests);
            }
          });

          requests.sort((a, b) {
            if (a.paymentDeadline == null || b.paymentDeadline == null) {
              return 0;
            }
            return a.paymentDeadline!.compareTo(b.paymentDeadline!);
          });

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_unmatchedNotifications.isNotEmpty) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kDarkGrey,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.notifications_active_rounded, color: Colors.amberAccent, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Mutasi DompetKu Belum Tercocokkan (${_unmatchedNotifications.length})',
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._unmatchedNotifications.take(5).map((u) {
                        final amt = NumberFormat.currency(
                          locale: 'id_ID',
                          symbol: 'Rp ',
                          decimalDigits: 0,
                        ).format(num.tryParse('${u['amount']}') ?? 0);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• $amt via ${u['app_source'] ?? 'QRIS'} (${u['payer_name'] ?? 'Pelanggan'}) — [${u['tenant_slug']}]',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
              ...requests.map((q) => _buildCard(context, q)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(BuildContext context, Queue q) {
    final d = _detailsMap[q.id];
    
    if (d == null) {
      return Container(
        height: 100,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: kDarkGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: kBrownAccent, strokeWidth: 2),
          ),
        ),
      );
    }

    final isExpired =
        q.paymentDeadline != null &&
        DateTime.now().isAfter(q.paymentDeadline!.toDate());
    final hasProof =
        q.paymentProofBase64 != null && q.paymentProofBase64!.isNotEmpty;

    return GestureDetector(
      onTap: () => _showDetail(context, q, d),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: kDarkGrey,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isExpired
                ? Colors.red
                : (hasProof ? Colors.green : Colors.orange),
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d['shop'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          d['customer'],
                          style: const TextStyle(
                            color: kTextGrey,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isExpired
                          ? Colors.red
                          : (hasProof ? Colors.green : Colors.orange),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isExpired
                          ? 'EXPIRED'
                          : (hasProof ? 'PROOF OK' : 'WAITING'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 11,
                    color: kTextGrey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      DateFormat(
                        'EEE d MMM HH:mm',
                      ).format(q.bookingTime.toDate()),
                      style: const TextStyle(
                        color: kTextGrey,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.hourglass_bottom,
                    size: 11,
                    color: kTextGrey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      q.paymentDeadline != null
                          ? DateFormat(
                              'd MMM HH:mm',
                            ).format(q.paymentDeadline!.toDate())
                          : 'No deadline',
                      style: TextStyle(
                        color: isExpired ? Colors.red : kTextGrey,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              if (q.totalPrice != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.money, size: 11, color: kBrownAccent),
                    const SizedBox(width: 4),
                    Text(
                      NumberFormat.currency(
                        locale: 'id_ID',
                        symbol: 'Rp ',
                        decimalDigits: 0,
                      ).format(q.expectedAmount ?? q.totalPrice),
                      style: const TextStyle(
                        color: kBrownAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (q.uniqueCode != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(Kode Unik +${q.uniqueCode})',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Queue q, Map<String, dynamic> d) {
    final noteCtrl = TextEditingController();
    final hasProof =
        q.paymentProofBase64 != null && q.paymentProofBase64!.isNotEmpty;
    final shopSlug = q.barbershopId.isNotEmpty
        ? q.barbershopId
        : 'febrian-barbershop';
    final tenantUnmatched = _unmatchedNotifications
        .where((u) => u['tenant_slug'] == shopSlug && u['dompetku_tx_id'] is String)
        .toList();
    final matchedCandidate = tenantUnmatched.cast<Map<String, dynamic>?>().firstWhere(
          (u) {
            final amt = (num.tryParse('${u?['amount']}') ?? -1).round();
            return (q.expectedAmount != null && amt == q.expectedAmount) ||
                (q.totalPrice != null && amt == q.totalPrice);
          },
          orElse: () => null,
        );
    String? selectedUnmatchedTxId = matchedCandidate?['dompetku_tx_id'] as String?;

    showModalBottomSheet(
      context: context,
      backgroundColor: kDarkGrey,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => StatefulBuilder(
        builder: (c, setModalState) => Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(c).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Verifikasi Pembayaran',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(c),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('Status', 'AWAITING PAYMENT', Colors.orange),
                    _row('Customer', d['customer']),
                    _row('Shop', d['shop']),
                    _row('Service', d['service']),
                    _row(
                      'Booking Time',
                      DateFormat(
                        'EEE d MMM HH:mm',
                      ).format(q.bookingTime.toDate()),
                    ),
                    if (q.estimatedDuration != null)
                      _row('Duration', '${q.estimatedDuration} min'),
                    if (q.totalPrice != null)
                      _row(
                        'Nominal Presisi QRIS',
                        NumberFormat.currency(
                          locale: 'id_ID',
                          symbol: 'Rp ',
                          decimalDigits: 0,
                        ).format(q.expectedAmount ?? q.totalPrice),
                        kBrownAccent,
                      ),
                    if (q.uniqueCode != null)
                      _row('Kode Unik DompetKu', '+Rp ${q.uniqueCode}', Colors.greenAccent),
                    if (q.paymentDeadline != null)
                      _row(
                        'Deadline',
                        DateFormat(
                          'EEE d MMM HH:mm',
                        ).format(q.paymentDeadline!.toDate()),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (hasProof) ...[
                const Text(
                  'Bukti Pembayaran',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 180,
                  child: AppImage(
                    imageUrl: q.paymentProofBase64!,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: c,
                      builder: (dc) => AlertDialog(
                        backgroundColor: kDarkGrey,
                        content: SingleChildScrollView(
                          child: AppImage(
                            imageUrl: q.paymentProofBase64!,
                            fit: BoxFit.contain,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dc),
                            child: const Text('Tutup'),
                          ),
                        ],
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[700],
                    minimumSize: const Size(double.infinity, 40),
                  ),
                  child: const Text('Lihat Full Size'),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Belum ada bukti pembayaran',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (tenantUnmatched.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Tautkan Mutasi DompetKu (Opsional)',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String?>(
                  initialValue: selectedUnmatchedTxId,
                  dropdownColor: kDarkGrey,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tanpa Tautan Mutasi DompetKu', style: TextStyle(color: Colors.white70)),
                    ),
                    ...tenantUnmatched.map((u) {
                      final txId = u['dompetku_tx_id'] as String;
                      final amt = NumberFormat.currency(
                        locale: 'id_ID',
                        symbol: 'Rp ',
                        decimalDigits: 0,
                      ).format(num.tryParse('${u['amount']}') ?? 0);
                      return DropdownMenuItem<String?>(
                        value: txId,
                        child: Text('$amt • ${u['app_source']} (${u['payer_name'] ?? txId})'),
                      );
                    }),
                  ],
                  onChanged: (val) => setModalState(() => selectedUnmatchedTxId = val),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Catatan (opsional)',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: noteCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'E.g. Nomor rekening tidak cocok, jumlah kurang',
                  hintStyle: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await _queueService.adminConfirmPayment(
                            q.id,
                            adminNotes: noteCtrl.text.trim().isEmpty
                                ? (hasProof ? null : 'Dikonfirmasi manual via mutasi QRIS/Tunai kasir')
                                : noteCtrl.text.trim(),
                          );
                          try {
                            final api = HttpApiClient();
                            await api.post('/api/payments/$shopSlug/verify-manual', {
                              'ticketNumber': q.orderId ?? q.id,
                              'actor': 'kasir_admin_app',
                              if (selectedUnmatchedTxId != null)
                                'unmatchedTxId': selectedUnmatchedTxId,
                            });
                            api.close();
                            await _loadUnmatchedFromBackend([shopSlug]);
                          } catch (_) {}
                          if (c.mounted) {
                            Navigator.pop(c);
                            if (c.mounted) {
                              ScaffoldMessenger.of(c).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Pembayaran dikonfirmasi',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          if (c.mounted) {
                            ScaffoldMessenger.of(c).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kBrownAccent,
                        minimumSize: const Size.fromHeight(44),
                        disabledBackgroundColor: Colors.grey,
                      ),
                      child: Text(hasProof ? 'Konfirmasi' : 'Konfirmasi Mutasi / Tunai'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await _queueService.adminRejectPayment(
                            q.id,
                            reason: noteCtrl.text.trim().isEmpty
                                ? 'Bukti tidak valid'
                                : noteCtrl.text.trim(),
                          );
                          if (c.mounted) {
                            Navigator.pop(c);
                            if (c.mounted) {
                              ScaffoldMessenger.of(c).showSnackBar(
                                const SnackBar(
                                  content: Text('Pembayaran ditolak'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          if (c.mounted) {
                            ScaffoldMessenger.of(c).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('Tolak'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _row(String label, String val, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: kTextGrey, fontSize: 12)),
          Text(
            val,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
