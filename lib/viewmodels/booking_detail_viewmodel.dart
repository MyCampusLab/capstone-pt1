import 'package:flutter/material.dart';
import 'package:geges_smartbarber/models/barbershop.dart';
import 'package:geges_smartbarber/models/barberman.dart';
import 'package:geges_smartbarber/models/service.dart' as model;
import 'package:geges_smartbarber/services/queue_service.dart';
import 'package:geges_smartbarber/services/barbershop_service.dart';
import 'package:geges_smartbarber/models/queue.dart';
import 'package:url_launcher/url_launcher.dart';

class BookingDetailViewModel extends ChangeNotifier {
  final QueueService _queueService;
  final BarbershopService _barbershopService;
  final String queueId;

  Barbershop? barbershop;
  Barberman? barberman;
  List<model.Service> services = [];
  bool metadataLoaded = false;
  
  // Stream untuk real-time updates queue
  Stream<Queue?> get queueStream => _queueService.streamQueueById(queueId);

  BookingDetailViewModel({
    required this.queueId,
    QueueService? queueService,
    BarbershopService? barbershopService,
  })  : _queueService = queueService ?? QueueService(),
        _barbershopService = barbershopService ?? BarbershopService() {
    loadMetadata();
  }

  Future<void> loadMetadata() async {
    try {
      final q = await _queueService.getQueueById(queueId);
      if (q != null) {
        final results = await Future.wait([
          _barbershopService.getBarbershopById(q.barbershopId),
          _barbershopService.getBarbermanById(q.barbermanId),
          _loadServices(q.serviceIds ?? (q.serviceId != null ? [q.serviceId!] : [])),
        ]);
        
        barbershop = results[0] as Barbershop?;
        barberman = results[1] as Barberman?;
        services = results[2] as List<model.Service>;
        metadataLoaded = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error loading metadata: $e");
    }
  }

  Future<List<model.Service>> _loadServices(List<String> ids) async {
    if (ids.isEmpty) return [];
    final all = await _barbershopService.getAllServices();
    return all.where((s) => ids.contains(s.id)).toList();
  }

  Future<void> contactSupport(BuildContext context, String bookingId) async {
    final String rawPhone = barbershop?.whatsappNumber?.replaceAll(RegExp(r'[^0-9]'), '') ?? '6287896903760';
    final String targetPhone = rawPhone.startsWith('0') ? '62${rawPhone.substring(1)}' : rawPhone;
    final String message = "Halo Admin ${barbershop?.name ?? 'SmartBarber'}, saya butuh bantuan untuk Booking ID: $bookingId";
    final Uri whatsappUrl = Uri.parse("https://wa.me/$targetPhone?text=${Uri.encodeComponent(message)}");
    if (!await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membuka WhatsApp support')),
        );
      }
    }
  }

  Future<void> handleWithdraw(BuildContext context) async {
    final confirm = await _showConfirmDialog(context, 'Tarik Pengajuan?', 'Batalkan permintaan refund dan aktifkan kembali pesanan Anda?');
    if (confirm == true) {
      try {
        await _queueService.withdrawCancellationRequest(queueId);
      } catch (e) { 
        if (!context.mounted) return;
        _showSnack(context, 'Gagal: $e', isError: true); 
      }
    }
  }

  Future<void> handleDeleteOrder(BuildContext context) async {
    final confirm = await _showConfirmDialog(context, 'Hapus Pesanan?', 'Pesanan akan dihapus permanen dari riwayat Anda.');
    if (confirm == true) {
      try {
        await _queueService.deleteQueue(queueId);
        if (!context.mounted) return;
        Navigator.pop(context); // Close detail screen
      } catch (e) {
        if (!context.mounted) return;
        _showSnack(context, 'Gagal menghapus: $e', isError: true);
      }
    }
  }

  Future<void> handleRequestCancellation(BuildContext context, {String? reason}) async {
    try {
      await _queueService.customerRequestCancellation(
        queueId, 
        reason: reason ?? 'Permintaan pembatalan dari customer',
      );
    } catch (e) { 
      if (!context.mounted) return;
      _showSnack(context, 'Gagal: $e', isError: true); 
    }
  }

  Future<void> cancelUnpaidOrder(BuildContext context) async {
    final confirm = await _showConfirmDialog(context, 'Batal?', 'Pesanan belum dibayar dan akan langsung dibatalkan.');
    if (confirm == true) {
      try {
        await _queueService.cancelQueue(queueId);
        if (!context.mounted) return;
        Navigator.pop(context);
      } catch (_) {
        if (!context.mounted) return;
        _showSnack(context, 'Gagal');
      }
    }
  }

  Future<bool?> _showConfirmDialog(BuildContext context, String t, String d) {
    return showDialog<bool>(context: context, builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(t, style: const TextStyle(color: Colors.white)), 
      content: Text(d, style: const TextStyle(color: Colors.white70)), 
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('KEMBALI')),
        ElevatedButton(
          onPressed: () => Navigator.pop(c, true), 
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC3A47B)), 
          child: const Text('OK', style: TextStyle(color: Colors.black))
        ),
      ]
    ));
  }

  void _showSnack(BuildContext context, String m, {bool isError = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m), 
      backgroundColor: isError ? const Color(0xFFD32F2F) : const Color(0xFFC3A47B)
    ));
  }
}
