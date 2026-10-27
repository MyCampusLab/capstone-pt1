// lib/screens/customer/payment_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // Required for compute
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geges_smartbarber/models/queue.dart';
import 'package:geges_smartbarber/services/queue_service.dart';
import 'package:geges_smartbarber/services/queue_service_contract.dart';
import 'package:geges_smartbarber/services/barbershop_service.dart';
import 'package:geges_smartbarber/screens/customer/special_orders_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:geges_smartbarber/l10n/generated/app_localizations.dart';
import 'package:geges_smartbarber/utils/emvco_qris_helper.dart';
import 'package:geges_smartbarber/services/http_api_client.dart';

// --- No-Op Service for Tenant Mode ---
class _NoOpQueueService implements QueueServiceContract {
  @override
  Future<dynamic> createQueue(Map<String, dynamic> queueData) async => null;
  @override
  Future<int> cancelExpiredAwaitingPaymentQueuesForCustomer(String customerId) async => 0;
  @override
  Future<int> cancelExpiredWaitingQueuesForCustomer(String customerId) async => 0;
  @override
  Future<void> cancelQueue(String queueId, {String reason = '', String? cancelledBy}) async {}
  @override
  Future<Queue?> getQueueById(String id) async => null;
  @override
  Stream<Queue?> streamQueueById(String id) async* { yield null; }
  @override
  Future<Queue?> resolveQueueForCustomerByIdOrOrder(String idOrOrderId, String customerId) async => null;
  @override
  Future<void> submitPaymentProofForQueue({required String queueId, required String userId, required String base64Proof}) async {}
}

class PaymentScreen extends StatefulWidget {
  final String orderId;
  final int totalPrice;
  final String? barbershopId;
  final String? barbermanId;
  final DateTime? bookingTime;
  final List<String>? serviceIds;
  final DateTime? paymentDeadline;
  final String? tenantId;
  final Future<void> Function({required String tenantId, required String base64, required String userId})? tenantPaymentHandler;
  final Future<void> Function({required String tenantId, required String userId, String? reason})? cancelTenantHandler;
  final QueueServiceContract? queueService;
  final String? testUserId;
  final ImagePicker? imagePicker;
  final bool disableTimer;
  final Future<void> Function()? submitProofHandler;
  final VoidCallback? onFinish;

  const PaymentScreen({
    super.key,
    required this.orderId,
    required this.totalPrice,
    this.barbershopId,
    this.barbermanId,
    this.bookingTime,
    this.serviceIds,
    this.paymentDeadline,
    this.tenantId,
    this.tenantPaymentHandler,
    this.cancelTenantHandler,
    this.queueService,
    this.testUserId,
    this.imagePicker,
    this.disableTimer = false,
    this.submitProofHandler,
    this.onFinish,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  static const Color kBrownAccent = Color(0xFFC3A47B);
  static const Color kSurface = Color(0xFF0F0F0F);
  static const Color kCardBg = Color(0xFF1A1A1A);
  static const Color kTextSecondary = Colors.white54;
  static const Color kSuccess = Color(0xFF4CAF50);

  late final QueueServiceContract _queueService;
  late final ImagePicker _picker;
  Timer? _timer;
  StreamSubscription<Queue?>? _queueSub;

  Duration _timeRemaining = const Duration(minutes: 15);
  bool _isLoading = true;
  bool _isSubmitting = false;
  File? _pickedImage;
  String? _resolvedQueueId;
  bool _hasUploadedProof = false;
  String? _paymentStatus; // 'awaiting', 'pending_verification', 'success', 'expired', 'rejected'
  int _uniqueCode = 1;
  int _expectedAmount = 0;
  String _dynamicQrisPayload = '';

  Map<String, int> _itemizedBill = {};
  @override
  void initState() {
    super.initState();
    _picker = widget.imagePicker ?? ImagePicker();
    _queueService = widget.queueService ?? (widget.tenantId != null ? _NoOpQueueService() : QueueService());
    _initTimer();
    _loadInitialData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _queueSub?.cancel();
    super.dispose();
  }

  void _initTimer() {
    if (widget.paymentDeadline != null) {
      final diff = widget.paymentDeadline!.difference(DateTime.now());
      _timeRemaining = diff.isNegative ? Duration.zero : diff;
    }
    if (!widget.disableTimer) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          if (_timeRemaining.inSeconds > 0) {
            _timeRemaining -= const Duration(seconds: 1);
            if (widget.queueService == null &&
                widget.tenantId == null &&
                _paymentStatus != 'success' &&
                _timeRemaining.inSeconds % 4 == 0) {
              _pollBackendPaymentStatus();
            }
          } else {
            timer.cancel();
            _paymentStatus = 'expired';
            
            // AUTO CANCEL: Ensure DB reflects expiration
            if (_resolvedQueueId != null) {
               _queueService.cancelQueue(_resolvedQueueId!, reason: 'Payment timeout (In-app timer)');
            }
          }
        });
      });
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    _uniqueCode = EmvcoQrisHelper.deriveDeterministicUniqueCode(widget.orderId);
    _expectedAmount = widget.totalPrice + _uniqueCode;
    String? resolvedStaticQris =
        (widget.barbershopId == null || widget.barbershopId == 'febrian-barbershop')
            ? EmvcoQrisHelper.defaultSampleStaticQris
            : null;

    if (widget.barbershopId != null &&
        widget.barbershopId!.isNotEmpty &&
        widget.tenantId == null) {
      try {
        final shop = await BarbershopService().getBarbershopById(widget.barbershopId!);
        final raw = shop?.qrisRawPayload?.trim();
        if (raw != null && raw.isNotEmpty && EmvcoQrisHelper.validateStaticQris(raw) == null) {
          resolvedStaticQris = raw;
        }
      } catch (_) {}
    }

    _dynamicQrisPayload = resolvedStaticQris != null
        ? EmvcoQrisHelper.generateDynamicQris(
            resolvedStaticQris,
            _expectedAmount > 0 ? _expectedAmount : 1,
          )
        : '';
    if (widget.tenantId != null) {
      _itemizedBill = {'Biaya Pendaftaran Tenant': widget.totalPrice};
      _paymentStatus = 'awaiting';
    } else {
      if (widget.serviceIds != null && widget.serviceIds!.isNotEmpty) {
        try {
          final shopService = BarbershopService();
          final services = await shopService.getServicesByIds(widget.serviceIds!);
          
          int servicesTotal = 0;
          Map<String, int> tempBill = {};
          
          for (var s in services) {
            tempBill[s.name] = s.price.toInt();
            servicesTotal += s.price.toInt();
          }

          if (widget.totalPrice > servicesTotal) {
             final diff = widget.totalPrice - servicesTotal;
             tempBill['Biaya Reservasi / Barber'] = diff;
          }

          if (mounted) {
            setState(() => _itemizedBill = tempBill);
          }
        } catch (e) {
           _itemizedBill = {'Total Layanan': widget.totalPrice};
        }
      } else {
        _itemizedBill = {'Layanan Barbershop': widget.totalPrice};
      }
    }

    final userId = widget.testUserId ?? FirebaseAuth.instance.currentUser?.uid;
    if (userId != null && widget.tenantId == null) {
      try {
        final q = await _queueService.resolveQueueForCustomerByIdOrOrder(widget.orderId, userId);
        if (q != null) {
          _resolvedQueueId = q.id;
          if (q.uniqueCode != null && q.uniqueCode! > 0) {
            _uniqueCode = q.uniqueCode!;
          }
          if (q.expectedAmount != null && q.expectedAmount! > 0) {
            _expectedAmount = q.expectedAmount!;
          } else {
            _expectedAmount = widget.totalPrice + _uniqueCode;
          }
          if (q.qrisDynamicPayload != null && q.qrisDynamicPayload!.isNotEmpty) {
            _dynamicQrisPayload = q.qrisDynamicPayload!;
          } else if (resolvedStaticQris != null) {
            _dynamicQrisPayload = EmvcoQrisHelper.generateDynamicQris(
              resolvedStaticQris,
              _expectedAmount > 0 ? _expectedAmount : 1,
            );
          }
          _listenToQueue(q.id);
        }
      } catch (e) {
        debugPrint("PaymentScreen Error: $e");
      }
    }

    setState(() => _isLoading = false);
  }


  Future<void> _pollBackendPaymentStatus() async {
    final shopSlug = (widget.barbershopId != null && widget.barbershopId!.isNotEmpty)
        ? widget.barbershopId!
        : 'febrian-barbershop';
    try {
      final api = HttpApiClient();
      final res = await api.get('/api/payments/$shopSlug/status/${widget.orderId}');
      api.close();
      if (!mounted || res is! Map) return;
      setState(() {
        if (res['uniqueCode'] is num && (res['uniqueCode'] as num) > 0) {
          _uniqueCode = (res['uniqueCode'] as num).toInt();
        }
        if (res['expectedAmount'] is num && (res['expectedAmount'] as num) > 0) {
          _expectedAmount = (res['expectedAmount'] as num).toInt();
        }
        if (res['qrisDynamicPayload'] is String &&
            (res['qrisDynamicPayload'] as String).isNotEmpty) {
          _dynamicQrisPayload = res['qrisDynamicPayload'] as String;
        }
        if (res['status'] == 'verified') {
          _paymentStatus = 'success';
          _timer?.cancel();
        }
      });
    } catch (_) {}
  }
  void _listenToQueue(String queueId) {
    _queueSub?.cancel();
    _queueSub = _queueService.streamQueueById(queueId).listen((q) {
      if (!mounted || q == null) return;
      
      String newStatus = 'awaiting';
      bool proofExists = (q.paymentProofBase64 != null && q.paymentProofBase64!.isNotEmpty) ||
                         (q.paymentProofUrl != null && q.paymentProofUrl!.isNotEmpty);

      if (q.status == QueueStatus.booked || q.status == QueueStatus.ongoing || q.status == QueueStatus.served) {
        newStatus = 'success';
      } else if (q.status == QueueStatus.cancelled) {
        newStatus = q.rejectionReason != null ? 'rejected' : 'expired';
      } else if (proofExists) {
        newStatus = 'pending_verification';
      }

      setState(() {
        _hasUploadedProof = proofExists;
        _paymentStatus = newStatus;
      });

      if (newStatus == 'success') _timer?.cancel();
    });
  }

  Future<void> _pickImage() async {
    if (_hasUploadedProof || _isSubmitting) return;
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image != null) {
        final file = File(image.path);
        if (await _isValidImageFile(file)) {
          setState(() => _pickedImage = file);
        } else {
          _showSnack("File tidak valid. Harap unggah gambar JPG/PNG.", isError: true);
        }
      }
    } catch (e) {
      _showSnack("Gagal mengambil gambar: $e", isError: true);
    }
  }

  Future<bool> _isValidImageFile(File file) async {
    try {
      final length = await file.length();
      if (length > 5 * 1024 * 1024) return false; // Max 5MB

      final fileStream = file.openRead(0, 4); // Read first 4 bytes
      final bytes = await fileStream.first;
      
      // Magic Numbers
      // JPG: FF D8 FF
      if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
      // PNG: 89 50 4E 47
      if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
      
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _submitProof() async {
    if (_pickedImage == null && widget.submitProofHandler == null) {
      _showSnack("Mohon pilih bukti transfer terlebih dahulu.", isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (widget.submitProofHandler != null) {
        await widget.submitProofHandler!();
        if (mounted) Navigator.pop(context);
        return;
      }

      final userId = widget.testUserId ?? FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception("User not logged in");

      // Aggressive compression to prevent Firestore 1MB document limit
      final Uint8List? compressedBytes = await FlutterImageCompress.compressWithFile(
        _pickedImage!.absolute.path,
        quality: 50, // 50 is enough for receipts
        minWidth: 1024,
        minHeight: 1024,
      );

      if (compressedBytes == null) throw Exception("Gagal mengompres gambar");
      
      final base64Img = await compute(base64Encode, compressedBytes);

      if (widget.tenantId != null && widget.tenantPaymentHandler != null) {
        await widget.tenantPaymentHandler!(tenantId: widget.tenantId!, base64: base64Img, userId: userId);
        if (mounted) {
           setState(() {
             _paymentStatus = 'success';
             _isLoading = false; 
           });
        }
      } else if (_resolvedQueueId != null) {
        await _queueService.submitPaymentProofForQueue(queueId: _resolvedQueueId!, userId: userId, base64Proof: base64Img);
        _showSnack("Bukti terkirim! Mohon tunggu verifikasi admin.", success: true);
      }
    } catch (e) {
      _showSnack("Gagal upload: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg, {bool isError = false, bool success = false}) {
    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : (success ? kSuccess : Colors.grey[800]),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: kSurface, body: Center(child: CircularProgressIndicator(color: kBrownAccent)));
    if (_paymentStatus == 'success') return _buildSuccessScreen();

    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () {
            if (widget.onFinish != null) {
              widget.onFinish!();
            } else {
              Navigator.pop(context);
            }
          }
        ),
        title: Text(l10n.paymentTitle, key: const Key('payment_screen_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildTimerHeader(l10n),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionHeader(l10n.itemDetails, Icons.receipt_long),
                  const SizedBox(height: 12),
                  _buildOrderSummary(l10n),
                  const SizedBox(height: 24),
                  _buildSectionHeader(l10n.transferTo, Icons.account_balance),
                  const SizedBox(height: 12),
                  _buildBankInfo(l10n),
                  const SizedBox(height: 24),
                  _buildSectionHeader(l10n.paymentSteps, Icons.help_outline),
                  const SizedBox(height: 12),
                  _buildInstructions(l10n),
                  const SizedBox(height: 24),
                  _buildSectionHeader(l10n.paymentProof, Icons.cloud_upload),
                  const SizedBox(height: 12),
                  _buildUploadSection(l10n),
                  const SizedBox(height: 20),
                  if (_paymentStatus == 'pending_verification')
                    _buildStatusBanner(l10n.verifying, Icons.hourglass_top, Colors.orange)
                  else if (_paymentStatus == 'rejected')
                    _buildStatusBanner(l10n.paymentRejected, Icons.error_outline, Colors.red)
                  else if (_paymentStatus == 'expired')
                    _buildStatusBanner(l10n.timeOut, Icons.timer_off, Colors.grey),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: _buildBottomAction(l10n),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: kBrownAccent, size: 18),
        const SizedBox(width: 8),
        Text(title.toUpperCase(), style: const TextStyle(color: kBrownAccent, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
      ],
    );
  }

  Widget _buildTimerHeader(AppLocalizations l10n) {
    bool isUrgent = _timeRemaining.inMinutes < 5;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: kCardBg,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.4), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Text(l10n.payBefore, style: const TextStyle(color: kTextSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            "${_timeRemaining.inMinutes.toString().padLeft(2,'0')}:${(_timeRemaining.inSeconds % 60).toString().padLeft(2,'0')}",
            style: TextStyle(color: isUrgent ? Colors.redAccent : kBrownAccent, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 4),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha:0.05))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.orderId, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
              Text("#${widget.orderId}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const Divider(height: 32, color: Colors.white10),
          ..._itemizedBill.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 14))),
                Text(NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(e.value), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          )),
          const Divider(height: 32, color: Colors.white10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Kode Unik Verifikasi Otomatis", style: TextStyle(color: Colors.white70, fontSize: 13)),
              Text(
                "+Rp $_uniqueCode",
                style: const TextStyle(color: kSuccess, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.totalBill, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text(
                NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(widget.totalPrice),
                style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total Bayar Presisi QRIS", style: TextStyle(color: kBrownAccent, fontWeight: FontWeight.bold, fontSize: 15)),
              Row(
                children: [
                  Text(
                    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_expectedAmount),
                    style: const TextStyle(color: kBrownAccent, fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _expectedAmount.toString()));
                      _showSnack(l10n.copySuccess, success: true);
                    },
                    child: const Icon(Icons.copy_rounded, size: 16, color: kBrownAccent),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBankInfo(AppLocalizations l10n) {
    const accNumber = "87705955837";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: kCardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kSuccess.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: kSuccess.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: const Text(
                      "QRIS DINAMIS (0% BIAYA ADMIN)",
                      style: TextStyle(color: kSuccess, fontWeight: FontWeight.w900, fontSize: 11),
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.bolt_rounded, color: kSuccess, size: 18),
                  const SizedBox(width: 4),
                  const Text("DompetKu Auto", style: TextStyle(color: kTextSecondary, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "Nominal Terkunci Otomatis: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_expectedAmount)}",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              const Text(
                "Uang masuk 100% langsung ke rekening barbershop. Begitu Anda membayar nominal presisi di atas via DANA/GoPay/OVO/BCA/SeaBank/Mandiri, status antrean otomatis berubah Lunas.",
                style: TextStyle(color: kTextSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              if (_dynamicQrisPayload.isNotEmpty) ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CustomPaint(
                          size: const Size(148, 148),
                          painter: _QrisMatrixPreviewPainter(_dynamicQrisPayload),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "NMID QRIS • Rp $_expectedAmount",
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dynamicQrisPayload,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _dynamicQrisPayload));
                        _showSnack(l10n.copySuccess, success: true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: kBrownAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                        child: const Text("Salin String QRIS", style: TextStyle(color: kBrownAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ]
              else
                const Text(
                  "QRIS toko belum dikonfigurasi. Silakan lakukan transfer manual atau pembayaran di kasir sesuai nominal presisi di atas.",
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11, height: 1.4),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBrownAccent.withValues(alpha: 0.2))),
          child: Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: const Text("BCA", style: TextStyle(color: Color(0xFF005CAA), fontWeight: FontWeight.w900, fontSize: 18)),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Bank Central Asia (Fallback Manual)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    const Text("FEBRIAN BARBERSHOP", style: TextStyle(color: kTextSecondary, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(accNumber, style: const TextStyle(color: kBrownAccent, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(const ClipboardData(text: accNumber));
                            _showSnack(l10n.copySuccess, success: true);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: kBrownAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: const Icon(Icons.copy_rounded, size: 16, color: kBrownAccent),
                          ),
                        )
                      ],
                    )
                  ],
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstructions(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kCardBg.withValues(alpha:0.5), borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          _buildStepRow("1", l10n.paymentStep1),
          const SizedBox(height: 12),
          _buildStepRow("2", l10n.paymentStep2),
          const SizedBox(height: 12),
          _buildStepRow("3", l10n.paymentStep3),
          const SizedBox(height: 12),
          _buildStepRow("4", l10n.paymentStep4),
        ],
      ),
    );
  }

  Widget _buildStepRow(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(radius: 10, backgroundColor: kBrownAccent, child: Text(number, style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold))),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4))),
      ],
    );
  }

  Widget _buildUploadSection(AppLocalizations l10n) {
    bool isLocked = _paymentStatus != 'awaiting'; 
    return InkWell(
      onTap: isLocked ? null : _pickImage,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: kCardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
          image: _pickedImage != null 
            ? DecorationImage(image: FileImage(_pickedImage!), fit: BoxFit.cover, opacity: 0.4)
            : null
        ),
        child: Center(
          child: _pickedImage == null 
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, size: 40, color: isLocked ? Colors.grey : kBrownAccent),
                  const SizedBox(height: 12),
                  Text(isLocked ? l10n.uploadLocked : l10n.tapToUpload, style: const TextStyle(color: kTextSecondary, fontWeight: FontWeight.w500)),
                ],
              )
            : Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: kSuccess, size: 40),
              ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha:0.3))),
      child: Row(children: [Icon(icon, color: color), const SizedBox(width: 12), Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)))]),
    );
  }

  Widget _buildBottomAction(AppLocalizations l10n) {
    bool isLocked = _paymentStatus != 'awaiting';
    String btnText = l10n.sendProof;
    if (_isSubmitting) btnText = l10n.sending;
    if (_paymentStatus == 'pending_verification') btnText = l10n.verificationPending;
    if (_paymentStatus == 'expired') btnText = l10n.timeOut;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(color: kSurface, border: Border(top: BorderSide(color: Colors.white.withValues(alpha:0.05)))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (isLocked || _isSubmitting) ? null : _submitProof,
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrownAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                disabledBackgroundColor: Colors.white10,
              ),
              child: _isSubmitting 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) 
                : Text(btnText, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
            ),
          ),
          if (widget.tenantId != null && !isLocked && !_isSubmitting) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                if (widget.cancelTenantHandler != null) {
                  widget.cancelTenantHandler!(tenantId: widget.tenantId!, userId: widget.testUserId ?? '');
                }
                Navigator.pop(context);
              },
              child: const Text("Batalkan Pendaftaran", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuccessScreen() {
    final l10n = AppLocalizations.of(context)!;
    final isTenant = widget.tenantId != null;

    final title = isTenant ? "Pendaftaran Berhasil Dikirim" : l10n.paymentAccepted;
    final desc = isTenant 
        ? "Bukti pembayaran Anda telah kami terima. Tim kami akan memverifikasi data Anda (maks 1x24 jam). Anda dapat memantau status pendaftaran di menu Profil > Pesanan Saya."
        : l10n.paymentSuccessDesc;
    final btnText = isTenant ? "Ke Menu Profil" : l10n.backToHome;

    return Scaffold(
      backgroundColor: kSurface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: kSuccess.withValues(alpha:0.1), shape: BoxShape.circle), child: const Icon(Icons.verified_rounded, size: 100, color: kSuccess)),
              const SizedBox(height: 32),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: kTextSecondary, fontSize: 16, height: 1.5)),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    if (isTenant) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const SpecialOrdersScreen()),
                        (route) => route.isFirst,
                      );
                    } else if (widget.onFinish != null) {
                      widget.onFinish!();
                    } else {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: kBrownAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: Text(btnText, style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _QrisMatrixPreviewPainter extends CustomPainter {
  final String payload;
  const _QrisMatrixPreviewPainter(this.payload);

  bool _isFinder(int r, int c, int n) {
    final topLeft = r < 7 && c < 7;
    final topRight = r < 7 && c >= n - 7;
    final bottomLeft = r >= n - 7 && c < 7;
    return topLeft || topRight || bottomLeft;
  }

  bool _finderModule(int r, int c) {
    if (r == 0 || r == 6 || c == 0 || c == 6) return true;
    if (r >= 2 && r <= 4 && c >= 2 && c <= 4) return true;
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const int grid = 25;
    final double cell = size.width / grid;
    final Paint dark = Paint()..color = Colors.black;

    for (int r = 0; r < grid; r++) {
      for (int c = 0; c < grid; c++) {
        bool fill = false;
        if (r < 7 && c < 7) {
          fill = _finderModule(r, c);
        } else if (r < 7 && c >= grid - 7) {
          fill = _finderModule(r, c - (grid - 7));
        } else if (r >= grid - 7 && c < 7) {
          fill = _finderModule(r - (grid - 7), c);
        } else if (r == 6 || c == 6) {
          fill = (r + c).isEven;
        } else if (!_isFinder(r, c, grid)) {
          final int idx = (r * grid + c) % payload.length;
          final int code = payload.codeUnitAt(idx);
          fill = ((code + r * 7 + c * 13) & 1) == 1;
        }
        if (fill) {
          canvas.drawRect(
            Rect.fromLTWH(c * cell, r * cell, cell * 0.92, cell * 0.92),
            dark,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrisMatrixPreviewPainter oldDelegate) =>
      oldDelegate.payload != payload;
}
