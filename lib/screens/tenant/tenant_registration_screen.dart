import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';

import 'package:geges_smartbarber/services/tenant_service.dart';
import 'package:geges_smartbarber/services/barbershop_service.dart';
import 'package:geges_smartbarber/services/location_service.dart';
import 'package:geges_smartbarber/services/queue_service.dart';
import 'package:geges_smartbarber/services/auth_service.dart';
import 'package:geges_smartbarber/services/email_service.dart';
import 'package:geges_smartbarber/utils/input_validators.dart';
import 'package:geges_smartbarber/widgets/document_upload_widget.dart';
import 'package:geges_smartbarber/widgets/tenant_guide_dialog.dart';
import 'package:geges_smartbarber/screens/legal/terms_page.dart';
import 'package:geges_smartbarber/screens/customer/payment_screen.dart';
import 'package:geges_smartbarber/screens/customer/home_screen.dart';

class TenantRegistrationScreen extends StatefulWidget {
  final TenantService? tenantService;
  final BarbershopService? barbershopService;
  final LocationService? locationService;
  final QueueService? queueService;
  final AuthService? authService;
  final String? currentUserId;
  final Future<String?> Function()? filePicker;
  final bool initialAcceptedTerms;
  final String? initialCompanyDocPath;
  final String? initialTaxDocPath;
  final bool skipGuide;

  final Future<void> Function(String tenantId)? testSubmitProofHandler;

  const TenantRegistrationScreen({
    super.key,
    this.tenantService,
    this.barbershopService,
    this.locationService,
    this.queueService,
    this.authService,
    this.currentUserId,
    this.filePicker,
    this.initialAcceptedTerms = false,
    this.initialCompanyDocPath,
    this.initialTaxDocPath,
    this.skipGuide = false,
    this.testSubmitProofHandler,
  });

  @override
  State<TenantRegistrationScreen> createState() =>
      _TenantRegistrationScreenState();
}

class _TenantRegistrationScreenState extends State<TenantRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameCtrl = TextEditingController();
  final _legalNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _ownerEmailCtrl = TextEditingController();
  final _ownerPhoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();

  String _plan = 'monthly'; // monthly/yearly
  bool _submitting = false;

  // New: terms acceptance and pre-uploaded documents
  bool _acceptedTerms = false;
  File? _companyDocFile;
  File? _taxDocFile;
  List<int>? _companyDocBytes;
  List<int>? _taxDocBytes;

  @override
  void initState() {
    super.initState();
    _acceptedTerms = widget.initialAcceptedTerms;
    if (widget.initialCompanyDocPath != null) {
      _companyDocFile = File(widget.initialCompanyDocPath!);
      try {
        _companyDocBytes = _companyDocFile!.readAsBytesSync();
      } catch (_) {}
    }
    if (widget.initialTaxDocPath != null) {
      _taxDocFile = File(widget.initialTaxDocPath!);
      try {
        _taxDocBytes = _taxDocFile!.readAsBytesSync();
      } catch (_) {}
    }
    // Auto-check for existing pending registration
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.skipGuide) {
        _showGuide();
      }
      _checkPendingRegistration();
    });
  }

  void _showGuide() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const TenantGuideDialog(),
    );
  }

  void _resetForm() {
    _businessNameCtrl.clear();
    _legalNameCtrl.clear();
    _ownerNameCtrl.clear();
    _ownerEmailCtrl.clear();
    _ownerPhoneCtrl.clear();
    _addressCtrl.clear();
    _taxIdCtrl.clear();
    if (mounted) {
      setState(() {
        _companyDocFile = null;
        _taxDocFile = null;
        _companyDocBytes = null;
        _taxDocBytes = null;
        _acceptedTerms = false;
        _plan = 'monthly';
      });
    }
  }

  void _navigateToProfile() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          initialIndex: 2, // Profile tab (index 2 setelah pembersihan tab AI)
          currentUserId: widget.currentUserId,
          barbershopService: widget.barbershopService,
          locationService: widget.locationService,
          queueService: widget.queueService,
          authService: widget.authService,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _checkPendingRegistration() async {
    String? userId = widget.currentUserId;
    if (userId == null) {
      try {
        userId = FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {
        return;
      }
    }
    if (userId == null) return;

    try {
      final fs = _tenantService.firestore;
      final existingQ = await fs
          .collection('tenants')
          .where('owner_uid', isEqualTo: userId)
          .where('status', whereIn: [
            'pending_payment',
            'awaiting_payment',
            'waiting_proof',
            'payment_submitted',
            'active',
          ])
          .get();

      if (existingQ.docs.isNotEmpty && mounted) {
        // Sort by newest first
        final docs = existingQ.docs.toList();
        docs.sort((a, b) {
          final aTs =
              (a.data()['created_at'] as Timestamp?)?.toDate() ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTs =
              (b.data()['created_at'] as Timestamp?)?.toDate() ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bTs.compareTo(aTs);
        });

        final doc = docs.first;
        final data = doc.data();
        final status = data['status'] as String?;
        
        if (status == 'active') {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Sudah Terdaftar'),
              content: const Text('Akun Anda sudah terdaftar sebagai Owner Barbershop. Silakan login menggunakan Aplikasi Admin.'),
              actions: [
                TextButton(onPressed: () { Navigator.pop(ctx); Navigator.pop(context); }, child: const Text('OK')),
              ],
            ),
          );
          return;
        }

        final paymentData = data['payment'] as Map<String, dynamic>?;
        final verificationStatus = paymentData?['verificationStatus'] as String?;
        final hasProof = (paymentData?['payment_proof_base64'] != null && paymentData!['payment_proof_base64'].toString().isNotEmpty) ||
                         (paymentData?['proofUrl'] != null && paymentData!['proofUrl'].toString().isNotEmpty);

        if (status == 'waiting_proof' || status == 'payment_submitted' || hasProof || verificationStatus == 'pending') {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Pendaftaran Sedang Diproses'),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Anda sudah mengirimkan bukti pembayaran.'),
                  SizedBox(height: 8),
                  Text('Status: Menunggu Verifikasi Admin'),
                  SizedBox(height: 8),
                  Text('Mohon cek berkala di menu My Orders, untuk update status.'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  }, 
                  child: const Text('Tutup'),
                ),
              ],
            ),
          );
          return;
        }

        // Resume flow
        final resume = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Lanjutkan Pendaftaran?'),
                content: const Text(
                  'Anda memiliki pendaftaran yang belum selesai (menunggu pembayaran). Ingin melanjutkannya?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Buat Baru'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Lanjutkan Bayar'),
                  ),
                ],
              ),
        );

        if (resume == true && mounted) {
          final invoice = data['invoice'] as Map<String, dynamic>?;
          final amount =
              invoice?['amount'] as int? ??
              data['registration_fee'] as int? ??
              _price;
          final deadline =
              (invoice?['payment_deadline'] as Timestamp?)?.toDate() ??
              DateTime.now().add(const Duration(hours: 1));

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder:
                  (_) => PaymentScreen(
                    onFinish: _navigateToProfile,
                    orderId: doc.id,
                    totalPrice: amount,
                    tenantId: doc.id,
                    tenantPaymentHandler:
                        ({
                          required String tenantId,
                          required String base64,
                          required String userId,
                        }) async {
                          await _tenantService.submitRegistrationPayment(
                            tenantId: tenantId,
                            proofBase64: base64,
                            userId: userId,
                          );
                        },
                    cancelTenantHandler:
                        ({
                          required String tenantId,
                          required String userId,
                          String? reason,
                        }) async {
                          await _tenantService.cancelRegistrationByOwner(
                            tenantId: tenantId,
                            userId: userId,
                            reason: reason,
                          );
                        },
                    disableTimer: false,
                    paymentDeadline: deadline,
                    testUserId: widget.currentUserId,
                    submitProofHandler:
                        widget.testSubmitProofHandler != null
                            ? () => widget.testSubmitProofHandler!(doc.id)
                            : null,
                  ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error checking pending registration: $e');
    }
  }

  TenantService get _tenantService => widget.tenantService ?? TenantService();

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _legalNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerEmailCtrl.dispose();
    _ownerPhoneCtrl.dispose();
    _addressCtrl.dispose();
    _taxIdCtrl.dispose();
    super.dispose();
  }

  int get _price => _plan == 'monthly' ? 300000 : 3000000;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final accepted = _acceptedTerms || widget.initialAcceptedTerms;
    if (!accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Anda harus menyetujui Perjanjian Tenant sebelum melanjutkan',
          ),
        ),
      );
      return;
    }

    String? userId = widget.currentUserId;
    if (userId == null) {
      try {
        userId = FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {}
    }
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anda harus login untuk mendaftar sebagai tenant'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // VALIDASI EMAIL: Cek apakah email sudah terdaftar sebagai user/pelanggan
      final emailToCheck = _ownerEmailCtrl.text.trim();
      final authService = widget.authService ?? AuthService();
      final isTaken = await authService.isEmailRegistered(emailToCheck);
      
      if (isTaken && mounted) {
        setState(() => _submitting = false);
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Email Sudah Terdaftar'),
            content: const Text(
              'Email yang Anda masukkan sudah digunakan oleh akun lain (pelanggan). '
              'Untuk mendaftar sebagai Tenant/Mitra, Anda WAJIB menggunakan email BARU '
              'yang belum pernah terdaftar di sistem Geges.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ganti Email')),
            ],
          ),
        );
        return;
      }

      final fs = _tenantService.firestore;
      final existingQ = await fs
          .collection('tenants')
          .where('owner_uid', isEqualTo: userId)
          .where(
            'status',
            whereIn: ['pending_payment', 'awaiting_payment', 'waiting_proof'],
          )
          .get();

      String? tenantId;

      final baseData = {
        'business_name': _businessNameCtrl.text.trim(),
        'legal_name': _legalNameCtrl.text.trim(),
        'owner_name': _ownerNameCtrl.text.trim(),
        'owner_email': _ownerEmailCtrl.text.trim(),
        'owner_phone': _ownerPhoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'tax_id': _taxIdCtrl.text.trim(),
        'plan': _plan,
        'registration_fee': _price,
        'owner_uid': userId,
        'status': 'awaiting_payment',
        'accepted_terms': accepted,
      };

      if (existingQ.docs.isNotEmpty) {
        tenantId = existingQ.docs.first.id;
        await _tenantService.updateTenantApplication(tenantId, baseData);
      } else {
        tenantId = await _tenantService.createTenantApplication(baseData);
      }

      if (_companyDocFile != null || _companyDocBytes != null) {
        final ref = await _tenantService.uploadTenantDocument(
          tenantId,
          _companyDocFile,
          bytes: _companyDocBytes,
          filename: 'company_doc_${DateTime.now().millisecondsSinceEpoch}',
        );
        await _tenantService.updateTenantApplication(tenantId, {
          'company_doc_ref': ref,
        });
      }
      if (_taxDocFile != null || _taxDocBytes != null) {
        final ref = await _tenantService.uploadTenantDocument(
          tenantId,
          _taxDocFile,
          bytes: _taxDocBytes,
          filename: 'tax_doc_${DateTime.now().millisecondsSinceEpoch}',
        );
        await _tenantService.updateTenantApplication(tenantId, {
          'tax_doc_ref': ref,
        });
      }

      await _tenantService.updateTenantApplication(tenantId, {
        'invoice_id': 'REG-${DateTime.now().millisecondsSinceEpoch}',
        'invoice': {
          'amount': _price,
          'currency': 'IDR',
          'status': 'waiting_proof',
          'created_at': Timestamp.now(),
          'payment_deadline': Timestamp.fromDate(
            DateTime.now().add(const Duration(hours: 1)),
          ),
        },
      });

      // KIRIM EMAIL KONFIRMASI (Fire & Forget)
      try {
        EmailService().sendTenantRegistrationEmail(
          _businessNameCtrl.text.trim(), 
          _ownerEmailCtrl.text.trim()
        );
      } catch (e) {
        debugPrint('Gagal mengirim email tenant: $e');
      }

      if (!mounted) return;
      
      // Reset form before navigating away to ensure clean state if user comes back
      _resetForm();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            onFinish: _navigateToProfile,
            orderId: tenantId!, 
            totalPrice: _price,
            tenantId: tenantId,
            tenantPaymentHandler:
                ({
                  required String tenantId,
                  required String base64,
                  required String userId,
                }) async {
                  await _tenantService.submitRegistrationPayment(
                    tenantId: tenantId,
                    proofBase64: base64,
                    userId: userId,
                  );
                },
            cancelTenantHandler:
                ({
                  required String tenantId,
                  required String userId,
                  String? reason,
                }) async {
                  await _tenantService.cancelRegistrationByOwner(
                    tenantId: tenantId,
                    userId: userId,
                    reason: reason,
                  );
                },
            disableTimer: false,
            paymentDeadline: DateTime.now().add(const Duration(hours: 1)),
            testUserId: widget.currentUserId,
            submitProofHandler: widget.testSubmitProofHandler != null
                ? () => widget.testSubmitProofHandler!(tenantId!)
                : null,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal mendaftar: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pendaftaran Franchise / Tenant')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _businessNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nama Bisnis (Barbershop)',
                ),
                validator: (v) => InputValidators.validateRequired(v, fieldName: 'Nama Bisnis'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _legalNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nama Legal Perusahaan',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ownerNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nama Lengkap Pemilik',
                  hintText: 'Masukkan nama sesuai KTP',
                ),
                validator: InputValidators.validateName,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ownerEmailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email Baru Khusus Bisnis',
                  hintText: 'contoh: barbersaya@gmail.com',
                  helperText: 'WAJIB email baru yang BELUM terdaftar sebagai pelanggan.',
                  helperStyle: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: InputValidators.validateEmail,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ownerPhoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nomor WhatsApp Pemilik',
                  prefixIcon: Icon(Icons.phone),
                  hintText: '0812xxxxxxxx',
                ),
                keyboardType: TextInputType.phone,
                validator: InputValidators.validatePhone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Alamat Lengkap Operasional',
                  prefixIcon: Icon(Icons.map),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _taxIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'NPWP / Tax ID (opsional)',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),

              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _showGuide,
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('Lihat Panduan Pendaftaran & Alur Mitra'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFC3A47B),
                  alignment: Alignment.centerLeft,
                ),
              ),

              Card(
                color: const Color(0xFF1B1B1B),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Persetujuan & Dokumen (wajib)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Checkbox(
                            value: _acceptedTerms,
                            onChanged: (v) =>
                                setState(() => _acceptedTerms = v ?? false),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const TermsPage(),
                                ),
                              ),
                              child: const Text(
                                'Saya menyetujui Perjanjian Tenant (termasuk potongan refund 10%) dan Kebijakan Aplikasi',
                                style: TextStyle(
                                  decoration: TextDecoration.underline,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Unggah dokumen awal: Surat Izin Usaha Perdagangan (SIUP) & Nomor Pokok Wajib Pajak (NPWP). Ukuran maksimal ~900KB per file.',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB9976E),
                              ),
                              icon: const Icon(Icons.upload_file),
                              label: Text(
                                _companyDocFile == null
                                    ? 'SIUP'
                                    : 'SIUP: ${_companyDocFile!.path.split('/').last}',
                                style: const TextStyle(color: Colors.black, fontSize: 12),
                              ),
                              onPressed: () async {
                                String? pickedPath;
                                if (widget.filePicker != null) {
                                  pickedPath = await widget.filePicker!.call();
                                } else {
                                  final res = await FilePicker.platform
                                      .pickFiles();
                                  if (res == null || res.files.single.path == null) {
                                    return;
                                  }
                                  pickedPath = res.files.single.path;
                                }
                                if (pickedPath == null) return;
                                final p = pickedPath;
                                final file = File(p);
                                final bytes = await file.readAsBytes();
                                setState(() {
                                  _companyDocFile = file;
                                  _companyDocBytes = bytes;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB9976E),
                              ),
                              icon: const Icon(Icons.upload_file),
                              label: Text(
                                _taxDocFile == null
                                    ? 'NPWP'
                                    : 'NPWP: ${_taxDocFile!.path.split('/').last}',
                                style: const TextStyle(color: Colors.black, fontSize: 12),
                              ),
                              onPressed: () async {
                                String? pickedPath;
                                if (widget.filePicker != null) {
                                  pickedPath = await widget.filePicker!.call();
                                } else {
                                  final res = await FilePicker.platform
                                      .pickFiles();
                                  if (res == null || res.files.single.path == null) {
                                    return;
                                  }
                                  pickedPath = res.files.single.path;
                                }
                                if (pickedPath == null) return;
                                final p = pickedPath;
                                final file = File(p);
                                final bytes = await file.readAsBytes();
                                setState(() {
                                  _taxDocFile = file;
                                  _taxDocBytes = bytes;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Text(
                'Pilih Paket',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment(value: 'monthly', label: Text('Bulanan')),
                  ButtonSegment(value: 'yearly', label: Text('Tahunan')),
                ],
                selected: <String>{_plan},
                onSelectionChanged: (Set<String> newSelection) => setState(() => _plan = newSelection.first),
              ),

              const SizedBox(height: 16),
              const Text(
                'Setelah menekan Daftar, Anda akan diarahkan ke halaman pembayaran.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: _submitting
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _submit,
                        child: Text('Daftar & Bayar ${_price.toString()}'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TenantContinueScreen extends StatefulWidget {
  final String tenantId;
  final int amount;
  final TenantService? tenantService;
  final BarbershopService? barbershopService;
  final LocationService? locationService;
  final QueueService? queueService;
  final AuthService? authService;
  final FirebaseFirestore? firestore;
  final Future<String?> Function()? filePicker;
  final Future<void> Function()? submitProofHandler;
  final String? currentUserId;

  const TenantContinueScreen({
    super.key,
    required this.tenantId,
    required this.amount,
    this.tenantService,
    this.barbershopService,
    this.locationService,
    this.queueService,
    this.authService,
    this.firestore,
    this.filePicker,
    this.submitProofHandler,
    this.currentUserId,
  });

  @override
  State<TenantContinueScreen> createState() => _TenantContinueScreenState();
}

class _TenantContinueScreenState extends State<TenantContinueScreen> {
  TenantService get _tenantService => widget.tenantService ?? TenantService();
  FirebaseFirestore get _fs => widget.firestore ?? FirebaseFirestore.instance;
  bool _isSubmitting = false;

  void _navigateToProfile() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          initialIndex: 2, // Profile tab (index 2 setelah pembersihan tab AI)
          currentUserId: widget.currentUserId,
          barbershopService: widget.barbershopService,
          locationService: widget.locationService,
          queueService: widget.queueService,
          authService: widget.authService,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _submitPaymentProof(File proofFile) async {
    setState(() => _isSubmitting = true);
    try {
      final bytes = await proofFile.readAsBytes();
      final base64Proof = base64Encode(bytes);
      const int limit = 950000;
      if (base64Proof.length > limit) {
        throw Exception(
          'Ukuran file terlalu besar. Silakan kompres atau crop gambar.',
        );
      }

      String userId = widget.currentUserId ?? 'unknown';
      if (userId == 'unknown') {
        try {
          userId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
        } catch (_) {}
      }

      await _tenantService.submitRegistrationPayment(
        tenantId: widget.tenantId,
        proofBase64: base64Proof,
        userId: userId,
      );

      await _fs.collection('tenants').doc(widget.tenantId).set({
        'invoice': {
          'status': 'payment_submitted',
          'submitted_at': Timestamp.now(),
        },
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bukti pembayaran terkirim. Pendaftaran sedang diproses.',
          ),
        ),
      );
      _navigateToProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim bukti pembayaran: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lengkapi Pendaftaran')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DocumentUploadWidget(
              tenantId: widget.tenantId,
              tenantService: _tenantService,
              label: 'Surat Izin Usaha / SIUP',
              onUploaded: (ref) async {
                await _tenantService.updateTenantApplication(widget.tenantId, {
                  'company_doc_ref': ref,
                });
              },
            ),
            const SizedBox(height: 12),
            DocumentUploadWidget(
              tenantId: widget.tenantId,
              tenantService: _tenantService,
              label: 'NPWP / Dokumen Pajak',
              onUploaded: (ref) async {
                await _tenantService.updateTenantApplication(widget.tenantId, {
                  'tax_doc_ref': ref,
                });
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Pembayaran pendaftaran: Rp ${widget.amount}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isSubmitting
                  ? null
                  : () async {
                      if (widget.submitProofHandler != null) {
                        setState(() => _isSubmitting = true);
                        try {
                          await widget.submitProofHandler!.call();
                          _navigateToProfile();
                        } finally {
                          if (mounted) setState(() => _isSubmitting = false);
                        }
                        return;
                      }

                      String? path;
                      if (widget.filePicker != null) {
                        path = await widget.filePicker!.call();
                        if (path == null) return;
                      } else {
                        final res = await FilePicker.platform.pickFiles();
                        if (res == null || res.files.single.path == null) {
                          return;
                        }
                        path = res.files.single.path!;
                      }

                      final file = File(path);
                      await _submitPaymentProof(file);
                    },
              icon: const Icon(Icons.upload_file),
              label: _isSubmitting
                  ? const Text('Mengirim...')
                  : const Text('Unggah Bukti Pembayaran'),
            ),
          ],
        ),
      ),
    );
  }
}
