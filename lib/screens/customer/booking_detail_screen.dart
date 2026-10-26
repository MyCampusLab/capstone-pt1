// lib/screens/customer/booking_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:geges_smartbarber/config/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart'; // Wajib ada provider
import 'package:geges_smartbarber/models/queue.dart';
import 'package:geges_smartbarber/services/queue_service.dart';
import 'package:geges_smartbarber/services/barbershop_service.dart';
import 'package:geges_smartbarber/widgets/app_image.dart';
import 'package:geges_smartbarber/viewmodels/booking_detail_viewmodel.dart';
import 'payment_screen.dart';

const Color kBrownAccent = AppColors.primary;
const Color kDarkGrey = AppColors.surface;
const Color kSurface = AppColors.background;
const Color kTextGrey = AppColors.textSecondary;
const Color kSuccess = AppColors.success;
const Color kError = AppColors.danger;
const Color kWarning = AppColors.warning;

class BookingDetailScreen extends StatelessWidget {
  final String queueId;
  final QueueService? queueService;
  final BarbershopService? barbershopService;

  const BookingDetailScreen({
    super.key,
    required this.queueId,
    this.queueService,
    this.barbershopService,
  });

  @override
  Widget build(BuildContext context) {
    // Inject ViewModel di sini
    return ChangeNotifierProvider(
      create: (_) => BookingDetailViewModel(
        queueId: queueId,
        queueService: queueService,
        barbershopService: barbershopService,
      ),
      child: const _BookingDetailView(),
    );
  }
}

class _BookingDetailView extends StatelessWidget {
  const _BookingDetailView();

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<BookingDetailViewModel>(context);

    return StreamBuilder<Queue?>(
      stream: viewModel.queueStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !viewModel.metadataLoaded) {
          return const Scaffold(backgroundColor: kSurface, body: Center(child: CircularProgressIndicator(color: kBrownAccent)));
        }
        
        final queue = snapshot.data;
        if (queue == null) {
          return const Scaffold(backgroundColor: kSurface, body: Center(child: Text('Data tidak ditemukan', style: TextStyle(color: Colors.white))));
        }

        final bool hasPaid = queue.paymentProofBase64 != null && queue.paymentProofBase64!.isNotEmpty;
        final bool isVerified = queue.verifiedBy != null && queue.verifiedBy!.isNotEmpty;
        final bool isRequested = queue.status == QueueStatus.cancellationRequested;

        return Scaffold(
          backgroundColor: kSurface,
          appBar: AppBar(
            title: const Text('Booking Detail', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: kSurface,
            elevation: 0,
            centerTitle: true,
          ),
          body: RefreshIndicator(
            onRefresh: viewModel.loadMetadata,
            color: kBrownAccent,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                children: [
                  _buildTicketCard(context, viewModel, queue, hasPaid, isVerified, isRequested),
                  if (queue.isRefunded == true || queue.status == QueueStatus.cancelled || queue.requestStatus == RequestStatus.rejected) 
                    _buildRefundInfo(context, queue),
                  const SizedBox(height: 24),
                  _buildTimelineSection(queue, hasPaid, isVerified, isRequested),
                  const SizedBox(height: 32),
                  _buildActionButtons(context, viewModel, queue, hasPaid, isVerified, isRequested),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildTicketCard(BuildContext context, BookingDetailViewModel vm, Queue queue, bool hasPaid, bool isVerified, bool isRequested) {
    return Container(
      decoration: BoxDecoration(
        color: kDarkGrey,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          // Header: Shop Name
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (vm.barbershop == null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: kError, borderRadius: BorderRadius.circular(4)),
                    child: const Text("TOKO TELAH DIHAPUS", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                Text(
                  vm.barbershop?.name.toUpperCase() ?? '(DATA TOKO TIDAK TERSEDIA)', 
                  style: TextStyle(
                    color: vm.barbershop == null ? kTextGrey : kBrownAccent, 
                    fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(vm.barbershop?.addres ?? '-', textAlign: TextAlign.center, style: const TextStyle(color: kTextGrey, fontSize: 12)),
                const SizedBox(height: 16),
                _statusBadge(queue, hasPaid, isVerified, isRequested),
              ],
            ),
          ),
          
          _buildDashedLine(),

          // Body: Booking Time & Barber
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                _infoColumn('WAKTU', DateFormat('HH:mm').format(queue.bookingTime.toDate())),
                const Spacer(),
                _infoColumn('TANGGAL', DateFormat('dd MMM yyyy').format(queue.bookingTime.toDate())),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kBrownAccent.withValues(alpha: 0.2),
                  ),
                  child: ClipOval(
                    child: AppImage(
                      imageUrl: vm.barberman?.imageUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorWidget: const Icon(Icons.person, color: kBrownAccent),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('HAIRSTYLIST', style: TextStyle(color: kTextGrey, fontSize: 10, fontWeight: FontWeight.bold)),
                      Text(vm.barberman?.name ?? 'Assigned by System', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _buildDashedLine(),

          // Services
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DETAIL LAYANAN', style: TextStyle(color: kTextGrey, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...vm.services.map((s) {
                  final note = queue.serviceNotes?[s.id];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(s.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            Text('Rp ${NumberFormat('#,###').format(s.price)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (note != null && note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Note: $note',
                              style: const TextStyle(color: kBrownAccent, fontSize: 12, fontStyle: FontStyle.italic),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                if (queue.paidBarberSelection == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Special Order Fee', style: TextStyle(color: kBrownAccent, fontSize: 13, fontStyle: FontStyle.italic)),
                        Text('Rp ${NumberFormat('#,###').format(queue.barberSelectionFee ?? 0)}', style: const TextStyle(color: kBrownAccent, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                const Divider(color: Colors.white10, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL BAYAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('Rp ${NumberFormat('#,###').format(queue.totalPrice ?? 0)}', style: const TextStyle(color: kBrownAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          
          // Footer
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Center(
              child: Text('BOOKING ID: ${queue.id.toUpperCase()}', style: const TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(Queue queue, bool hasPaid, bool isVerified, bool isRequested) {
    final bool actuallyPaid = hasPaid || (queue.paymentProofUrl != null && queue.paymentProofUrl!.isNotEmpty);
    
    String label = 'BELUM BAYAR'; 
    Color color = Colors.orange;

    if (queue.status == QueueStatus.cancelled || queue.status.value == 'cancelled') { 
      label = 'DIBATALKAN'; color = kError; 
    } else if (queue.status == QueueStatus.cancellationRequested || isRequested) { 
      label = 'PERMOHONAN PEMBATALAN'; color = Colors.orange; 
    } else if (queue.status == QueueStatus.served || queue.status.value == 'served') {
      label = 'SELESAI'; color = kSuccess;
    } else if (queue.status == QueueStatus.ongoing || queue.status.value == 'ongoing') {
      label = 'SEDANG DIPROSES'; color = Colors.blue;
    } else if (queue.status == QueueStatus.booked || queue.status.value == 'booked') {
      label = 'TERJADWAL'; color = kSuccess;
    } else if (actuallyPaid) { 
      label = 'MENUNGGU VERIFIKASI'; color = Colors.amber; 
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStep(String title, String subtitle, bool isDone, {bool isLast = false, bool isCurrent = false}) {
    final Color color = isDone ? kBrownAccent : Colors.white24;
    final Color textColor = isDone ? Colors.white : Colors.white38;

    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrent ? Colors.transparent : color,
                  border: isCurrent ? Border.all(color: kBrownAccent, width: 2) : null,
                ),
                child: isDone && !isCurrent ? const Icon(Icons.check, size: 12, color: Colors.black) : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: color,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 11)),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: kTextGrey, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildDashedLine() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: List.generate(30, (index) => Expanded(
          child: Container(
            color: index % 2 == 0 ? Colors.transparent : Colors.white10,
            height: 1,
          ),
        )),
      ),
    );
  }

  Widget _buildTimelineSection(Queue queue, bool hasPaid, bool isVerified, bool isRequested) {
    final bool adminVerified = queue.status == QueueStatus.booked || queue.status == QueueStatus.ongoing || queue.status == QueueStatus.served;
    final bool isOngoing = queue.status == QueueStatus.ongoing || queue.status == QueueStatus.served;
    final bool isServed = queue.status == QueueStatus.served;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('TRACKING STATUS', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        _buildStep('Booking Dibuat', 'Pesanan Anda telah diterima sistem', true),
        _buildStep('Pembayaran', actuallyPaid(queue, hasPaid) ? 'Bukti transfer telah diterima' : 'Menunggu penyelesaian pembayaran', actuallyPaid(queue, hasPaid)),
        _buildStep('Verifikasi Admin', adminVerified ? 'Pembayaran valid & Jadwal terkunci' : 'Menunggu validasi pembayaran', adminVerified),
        _buildStep('Sedang Dicukur', isOngoing ? 'Hairstylist sedang memberikan layanan' : 'Menunggu giliran layanan', isOngoing),
        if (isRequested) _buildStep('Refund', 'Dana dalam proses pengembalian', true, isCurrent: true),
        _buildStep('Selesai', 'Selesai layanan dan meninggalkan barbershop', isServed, isLast: true),
      ],
    );
  }

  bool actuallyPaid(Queue q, bool hasPaid) {
    return hasPaid || (q.paymentProofUrl != null && q.paymentProofUrl!.isNotEmpty);
  }

  Widget _buildRefundInfo(BuildContext context, Queue queue) {
    final proof = queue.refundProofBase64;
    final bool isTextProof = proof != null && proof.startsWith('REF:');
    final String proofText = isTextProof ? proof.substring(4) : (proof ?? '-');
    final String reason = queue.refundReason ?? queue.rejectionReason ?? queue.cancellationReason ?? '-';

    return Container(
      margin: const EdgeInsets.only(top: 16),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kDarkGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('INFORMASI PEMBATALAN / REFUND', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Alasan: $reason', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          
          if (proof != null && proof.isNotEmpty) ...[
            const Text('Bukti Refund:', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            if (isTextProof)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                child: SelectableText(proofText, style: const TextStyle(color: Colors.white, fontFamily: 'Monospace')),
              )
            else
              GestureDetector(
                onTap: () => _showFullImage(context, proof),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AppImage(
                      imageUrl: proof,
                      height: 180,
                      borderRadius: BorderRadius.circular(12),
                      fit: BoxFit.cover,
                      errorWidget: Container(
                        color: Colors.black26,
                        child: const Icon(Icons.broken_image, color: Colors.white24),
                      ),
                    ),
                    const Icon(Icons.zoom_in, color: Colors.white70, size: 40),
                  ],
                ),
              )
          ],
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context, String base64) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: AppImage(imageUrl: base64, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  tooltip: 'Tutup tampilan gambar',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, BookingDetailViewModel vm, Queue queue, bool hasPaid, bool isVerified, bool isRequested) {
    // 1. Status: Refund Requested -> Withdraw option
    if (isRequested) {
      return Column(
        children: [
          ElevatedButton(
            onPressed: () => vm.handleWithdraw(context), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
            child: const Text('TARIK PENGAJUAN REFUND', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          ),
          const SizedBox(height: 16),
          _buildCustomerServiceButton(context, vm, queue.id),
        ],
      );
    }

    // 2. Status: Cancelled or Served -> Delete option (Cleanup)
    if (queue.status == QueueStatus.cancelled || queue.status == QueueStatus.served) {
      return Column(
        children: [
          _buildCustomerServiceButton(context, vm, queue.id),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => vm.handleDeleteOrder(context),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('HAPUS PESANAN', style: TextStyle(color: Colors.white54)),
          ),
        ],
      );
    }

    // 3. Status: Waiting Payment -> Pay or Cancel
    if (!hasPaid) {
      return Column(children: [
        ElevatedButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(orderId: queue.id, totalPrice: queue.totalPrice ?? 0))),
          style: ElevatedButton.styleFrom(backgroundColor: kBrownAccent, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('BAYAR SEKARANG', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        const SizedBox(height: 16),
        TextButton(onPressed: () => vm.cancelUnpaidOrder(context), child: const Text('Batalkan Pesanan', style: TextStyle(color: kError))),
      ]);
    }

    // Check if status is effectively confirmed regardless of 'verifiedBy' field
    final bool isStatusConfirmed = queue.status == QueueStatus.booked || queue.status == QueueStatus.ongoing || queue.status == QueueStatus.served;

    // 4. Status: Paid but Not Verified (and NOT confirmed via status) -> Wait + Info
    if (hasPaid && !isStatusConfirmed) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05), 
              borderRadius: BorderRadius.circular(16), 
              border: Border.all(color: Colors.white10)
            ),
            child: Column(children: [
              const Text(
                'Pembayaran sedang diverifikasi admin. Mohon tunggu.', 
                textAlign: TextAlign.center, 
                style: TextStyle(color: Colors.white70, fontSize: 13)
              ),
              const SizedBox(height: 16),
              _buildCustomerServiceButton(context, vm, queue.id),
            ]),
          ),
          const SizedBox(height: 12),
          const Text(
            'Pengajuan refund/pembatalan dapat dilakukan setelah verifikasi selesai.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      );
    }

    // 5. Status: Booked (Verified) -> Request Refund & CS
    if (queue.status == QueueStatus.booked) {
      return Column(
        children: [
          OutlinedButton(
            onPressed: () => _confirmCancellation(context, vm, queue), 
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kWarning), 
              minimumSize: const Size.fromHeight(50), 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ), 
            child: const Text('MINTA REFUND / BATAL', style: TextStyle(color: kWarning, fontWeight: FontWeight.bold))
          ),
          const SizedBox(height: 16),
          _buildCustomerServiceButton(context, vm, queue.id),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _confirmCancellation(BuildContext context, BookingDetailViewModel vm, Queue queue) async {
    final double total = queue.totalPrice?.toDouble() ?? 0.0;
    final double fee = total * 0.1;
    final double refund = total - fee;
    final TextEditingController reasonCtrl = TextEditingController();
    bool isAgreed = false; // Move outside builder

    final bool? confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: kDarkGrey,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: kWarning, size: 28),
                    SizedBox(width: 12),
                    Expanded(child: Text("Konfirmasi Pembatalan", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Reason field
                const Text("Alasan Pembatalan", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Contoh: Salah pilih jadwal...",
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      _calcRow("Total Bayar", total),
                      _calcRow("Biaya Admin (10%)", -fee, isRed: true),
                      const Divider(color: Colors.white10, height: 24),
                      _calcRow("Estimasi Refund", refund, isBold: true, color: kSuccess),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text("Kebijakan Refund:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                const Text("• Pengajuan akan diverifikasi admin (max 1x24 jam).", style: TextStyle(color: kTextGrey, fontSize: 12)),
                const Text("• Dana dikembalikan setelah disetujui.", style: TextStyle(color: kTextGrey, fontSize: 12)),
                const SizedBox(height: 20),
                
                GestureDetector(
                  onTap: () => setModalState(() => isAgreed = !isAgreed),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isAgreed, 
                        activeColor: kWarning,
                        checkColor: Colors.black,
                        onChanged: (v) => setModalState(() => isAgreed = v ?? false),
                      ),
                      const Expanded(
                        child: Text("Saya setuju dengan potongan biaya 10% dan kebijakan di atas.", style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Colors.white24)), child: const Text("KEMBALI", style: TextStyle(color: Colors.white70)))),
                    const SizedBox(width: 16),
                    Expanded(child: ElevatedButton(
                      onPressed: isAgreed ? () => Navigator.pop(ctx, true) : null, 
                      style: ElevatedButton.styleFrom(backgroundColor: kWarning, disabledBackgroundColor: Colors.white10, padding: const EdgeInsets.symmetric(vertical: 16)), 
                      child: const Text("AJUKAN REFUND", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))
                    )),
                  ],
                ),
              ],
            ),
          );
        }
      ),
    );

    if (confirm == true) {
      // ignore: use_build_context_synchronously
      await vm.handleRequestCancellation(context, reason: reasonCtrl.text.trim());
    }
  }

  Widget _calcRow(String label, double val, {bool isRed = false, bool isBold = false, Color color = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: kTextGrey)),
          Text(
            NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(val),
            style: TextStyle(color: isRed ? kError : color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 16 : 14),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerServiceButton(BuildContext context, BookingDetailViewModel vm, String bookingId) {
    return ElevatedButton.icon(
      onPressed: () => vm.contactSupport(context, bookingId), 
      icon: const Icon(Icons.chat_bubble_outline, size: 20, color: Colors.black), 
      label: const Text('HUBUNGI ADMIN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white, 
        elevation: 0,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
      ),
    );
  }
}
