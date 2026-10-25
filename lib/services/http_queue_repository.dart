import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geges_smartbarber/models/queue.dart';
import 'http_api_client.dart';
import 'queue_service_contract.dart';

class HttpQueueRepository implements QueueServiceContract {
  final HttpApiClient _apiClient;
  final Map<String, StreamController<Queue?>> _queueControllers = {};

  HttpQueueRepository({HttpApiClient? apiClient})
      : _apiClient = apiClient ?? HttpApiClient();

  // =========================================================================
  // MULTI-TENANT BACKEND CORE API
  // =========================================================================

  /// Mengambil daftar 3 mitra barbershop dari PostgreSQL backend
  Future<List<Map<String, dynamic>>> getTenants() async {
    final res = await _apiClient.get('/api/tenants');
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// Mengambil katalog kapster dan layanan spesifik tenant
  Future<Map<String, dynamic>> getTenantCatalog(String slug) async {
    final res = await _apiClient.get('/api/tenants/$slug/catalog');
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return {};
  }

  /// Booking tiket antrean dengan perhitungan Fuzzy Sugeno & Smart Dispatch di server
  Future<Map<String, dynamic>> bookQueue({
    required String tenantSlug,
    required String customerName,
    required String customerPhone,
    required int serviceId,
    dynamic barberId = 'smart',
    String bookingType = 'online_app',
  }) async {
    final payload = {
      'tenantSlug': tenantSlug,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'serviceId': serviceId,
      'barberId': barberId,
      'bookingType': bookingType,
    };

    final res = await _apiClient.post('/api/queue/book', payload);
    final result = Map<String, dynamic>.from(res as Map);
    await saveActiveTicketLocally(result, tenantSlug);
    return result;
  }

  /// Menyimpan tiket aktif ke memori lokal HP (Offline-First Ticket Cache)
  Future<void> saveActiveTicketLocally(Map<String, dynamic> ticket, String tenantSlug) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enriched = Map<String, dynamic>.from(ticket);
      enriched['tenantSlug'] = tenantSlug;
      await prefs.setString('fbrn_active_ticket', jsonEncode(enriched));
    } catch (e) {
      debugPrint('[HttpQueueRepository] Error saving ticket locally: $e');
    }
  }

  /// Mengambil tiket aktif dari cache lokal HP saat offline / aplikasi dibuka ulang
  Future<Map<String, dynamic>?> getActiveTicketLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('fbrn_active_ticket');
      if (raw != null && raw.isNotEmpty) {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (e) {
      debugPrint('[HttpQueueRepository] Error reading local ticket: $e');
    }
    return null;
  }

  /// Menghapus tiket aktif lokal saat potong rambut selesai
  Future<void> clearActiveTicketLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fbrn_active_ticket');
    } catch (_) {}
  }

  /// Mengecek status live tiket ke server
  Future<Map<String, dynamic>?> fetchTicketStatus(String tenantSlug, String ticketNumber) async {
    try {
      final res = await _apiClient.get('/api/queue/ticket/$tenantSlug/$ticketNumber');
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return null;
  }

  /// Mengunggah gambar via presigned URL (S3/R2) - Zero Base64 di database
  Future<String?> uploadPaymentProofS3({
    required String filename,
    required String contentType,
  }) async {
    final res = await _apiClient.post('/api/media/presign-upload', {
      'filename': filename,
      'contentType': contentType,
    });
    if (res is Map && res.containsKey('publicUrl')) {
      return res['publicUrl'] as String?;
    }
    return null;
  }
  /// Stream antrean per tenant untuk pembaruan instan di layar kasir & pelanggan
  Stream<Map<String, dynamic>> streamTenantLiveQueue(String tenantSlug) {
    final ctrl = StreamController<Map<String, dynamic>>.broadcast();
    // Polling / WebSocket event bridge
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (ctrl.isClosed) {
        timer.cancel();
        return;
      }
      try {
        final catalog = await getTenantCatalog(tenantSlug);
        if (!ctrl.isClosed) {
          ctrl.add(catalog);
        }
      } catch (_) {}
    });
    return ctrl.stream;
  }


  // =========================================================================
  // IMPLEMENTASI QUEUE SERVICE CONTRACT
  // =========================================================================
  @override
  Future<dynamic> createQueue(Map<String, dynamic> queueData) async {
    final rawShopId = (queueData['barbershop_id'] ?? queueData['barbershopId'] ?? 'febrian-barbershop').toString();
    final tenantSlug = rawShopId.contains('-') ? rawShopId : 'febrian-barbershop';

    final customerName = (queueData['customer_name'] ?? queueData['customerName'] ?? 'Pelanggan').toString();
    final customerPhone = (queueData['phone_number'] ?? queueData['customerPhone'] ?? '08123456789').toString();

    int serviceId = 1;
    if (queueData['service_ids'] is List && (queueData['service_ids'] as List).isNotEmpty) {
      final parsed = int.tryParse((queueData['service_ids'] as List).first.toString());
      if (parsed != null) serviceId = parsed;
    }

    final rawBarberId = queueData['barberman_id'] ?? queueData['barberId'];
    dynamic barberId = 'smart';
    if (rawBarberId != null && rawBarberId.toString().isNotEmpty && rawBarberId != 'auto' && rawBarberId != 'smart') {
      final parsedB = int.tryParse(rawBarberId.toString());
      barberId = parsedB ?? 'smart';
    }

    try {
      final res = await bookQueue(
        tenantSlug: tenantSlug,
        customerName: customerName,
        customerPhone: customerPhone,
        serviceId: serviceId,
        barberId: barberId,
        bookingType: 'online_app',
      );
      return res;
    } catch (e) {
      debugPrint('[HttpQueueRepository] Error creating queue on backend: $e');
      rethrow;
    }
  }


  @override
  Future<Queue?> getQueueById(String id) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('queues').doc(id).get();
      if (doc.exists && doc.data() != null) {
        return Queue.fromFirestore(doc);
      }
    } catch (e) {
      debugPrint('[HttpQueueRepository] Error fetching queue $id: $e');
    }
    return null;
  }

  @override
  Future<Queue?> resolveQueueForCustomerByIdOrOrder(String idOrOrderId, String customerId) async {
    final direct = await getQueueById(idOrOrderId);
    if (direct != null) return direct;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('queues')
          .where('order_id', isEqualTo: idOrOrderId)
          .where('customer_id', isEqualTo: customerId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return Queue.fromFirestore(snap.docs.first);
      }
    } catch (e) {
      debugPrint('[HttpQueueRepository] resolveQueue error: $e');
    }
    return null;
  }

  @override
  Future<void> submitPaymentProofForQueue({
    required String queueId,
    required String userId,
    required String base64Proof,
  }) async {
    // Generate S3 URL or store proof
    try {
      await FirebaseFirestore.instance.collection('queues').doc(queueId).update({
        'payment_proof_base64': base64Proof,
        'payment_submitted_at': FieldValue.serverTimestamp(),
        'status': 'awaiting_payment',
      });
    } catch (e) {
      debugPrint('[HttpQueueRepository] submitPaymentProof error: $e');
    }
  }

  @override
  Stream<Queue?> streamQueueById(String id) {
    if (!_queueControllers.containsKey(id)) {
      final ctrl = StreamController<Queue?>.broadcast();
      _queueControllers[id] = ctrl;

      FirebaseFirestore.instance.collection('queues').doc(id).snapshots().listen((doc) {
        if (!ctrl.isClosed) {
          if (doc.exists && doc.data() != null) {
            ctrl.add(Queue.fromFirestore(doc));
          } else {
            ctrl.add(null);
          }
        }
      }, onError: (err) {
        debugPrint('[HttpQueueRepository] Stream error for $id: $err');
      });
    }
    return _queueControllers[id]!.stream;
  }

  @override
  Future<void> cancelQueue(String queueId, {String reason = '', String? cancelledBy}) async {
    try {
      await FirebaseFirestore.instance.collection('queues').doc(queueId).update({
        'status': 'cancelled',
        'cancellation_reason': reason,
        'cancelled_by': cancelledBy,
        'cancelled_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[HttpQueueRepository] cancelQueue error: $e');
    }
  }

  @override
  Future<int> cancelExpiredAwaitingPaymentQueuesForCustomer(String customerId) async {
    return 0;
  }

  @override
  Future<int> cancelExpiredWaitingQueuesForCustomer(String customerId) async {
    return 0;
  }
}
