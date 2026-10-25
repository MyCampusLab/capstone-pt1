// lib/services/barbershop_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart'; // for debugPrint
import 'package:intl/intl.dart'; // for DateFormat
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geges_smartbarber/models/barbershop.dart';
import 'package:geges_smartbarber/models/barberman.dart';
import 'package:geges_smartbarber/models/service.dart';
import 'package:geges_smartbarber/models/promo_banner.dart';
import 'package:geges_smartbarber/models/queue.dart';
import 'package:geges_smartbarber/models/user_data.dart';

class BarbershopService {
  final FirebaseFirestore _firestore;
  
  // Cache sederhana untuk mengurangi read Firestore saat search/home reload
  List<Barbershop>? _cachedBarbershops;
  DateTime? _lastCacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  // Allow injecting a custom Firestore instance for testing
  BarbershopService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  // -----------------------
  // BARBERSHOP FUNCTIONS
  // -----------------------
  Future<List<Barbershop>> getAllBarbershops({bool forceRefresh = false}) async {
    try {
      // Cek cache validitas
      if (!forceRefresh && 
          _cachedBarbershops != null && 
          _lastCacheTime != null && 
          DateTime.now().difference(_lastCacheTime!) < _cacheDuration) {
        return _cachedBarbershops!;
      }

      // Filter hanya yang aktif secara sistem (isActive == true)
      // isOpen (buka/tutup harian) tetap diambil untuk ditampilkan statusnya
      // Optimization: Limit to 100 recent shops to prevent memory bloat on large datasets
      final snapshot = await _firestore.collection('barbershops')
          .where('isActive', isEqualTo: true)
          .limit(100) 
          .get();
      
      // Log teknis untuk pemantauan data Firestore
      debugPrint("DEBUG FIRESTORE FETCH");
      debugPrint("Koleksi: barbershops (Active Only)");
      debugPrint("Jumlah Dokumen: ${snapshot.docs.length}");
      if (snapshot.docs.isNotEmpty) {
        debugPrint("Data Sample JSON:");
        debugPrint(snapshot.docs.first.data().toString());
      }
      debugPrint("END DEBUG FIRESTORE FETCH");

      final list = snapshot.docs.map((doc) => Barbershop.fromFirestore(doc)).toList();
      final result = list.isNotEmpty ? list : _getPartnerBarbershopsStatic();
      
      // Update cache dengan data valid
      _cachedBarbershops = result;
      _lastCacheTime = DateTime.now();
      
      return result;
    } catch (e) {
      debugPrint('Error getAllBarbershops: $e, using partner barbershops fallback');
      final fallback = _getPartnerBarbershopsStatic();
      _cachedBarbershops = fallback;
      _lastCacheTime = DateTime.now();
      return fallback;
    }
  }
  /// Data statis terverifikasi 3 mitra barbershop untuk pengujian offline / skripsi
  static List<Barbershop> _getPartnerBarbershopsStatic() {
    return [
      Barbershop(
        id: 'febrian-barbershop',
        name: 'Febrian Barbershop',
        addres: 'Mejasem Barat, Kec. Kramat, Kab. Tegal',
        googleMapsUrl: 'https://share.google/DoR5RxMYsNkld66Qf',
        imageUrl: 'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?w=800',
        services: ['Potong Rambut Standar', 'Skin Fade & Beard', 'Pewarnaan'],
        facilities: ['AC', 'Free WiFi', 'Lounge', 'Full Music'],
        openHour: 9,
        closeHour: 21,
        isOpen: true,
        isActive: true,
      ),
      Barbershop(
        id: 'rr-barber-studio',
        name: 'RR Barber Studio',
        addres: 'Tegal, Jawa Tengah',
        googleMapsUrl: 'https://share.google/aCDF3ysRtOByKVCkA',
        imageUrl: 'https://images.unsplash.com/photo-1585747860715-2ba37e788b70?w=800',
        services: ['Signature Haircut', 'Fade Haircut', 'Coloring'],
        facilities: ['AC', 'Signature Styling', 'Coffee & Tea'],
        openHour: 10,
        closeHour: 21,
        isOpen: true,
        isActive: true,
      ),
      Barbershop(
        id: 'stupid-culture',
        name: 'Stupid Culture Barbershop',
        addres: 'Jl. Kapten Ismail No. 20, Kota Tegal (depan SJT Custom)',
        imageUrl: 'https://images.unsplash.com/photo-1621605815971-fbc98d665033?w=800',
        services: ['Gentleman Haircut (AC)', 'Taper / Skin Fade', 'Hair Coloring'],
        facilities: ['AC', 'Modern Styling', 'Music', 'Beverages'],
        openHour: 9,
        closeHour: 21,
        isOpen: true,
        isActive: true,
        whatsappNumber: '0857-2756-6125',
        instagramUrl: 'https://www.instagram.com/stup.idculture/',
      ),
    ];
  }

  // -----------------------
  // REAL-TIME STREAMS
  // -----------------------
  Stream<List<Barbershop>> streamAllBarbershops() {
    return _firestore.collection('barbershops')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => Barbershop.fromFirestore(doc)).toList();
        });
  }

  Stream<Barbershop?> streamBarbershopById(String id) {
    return _firestore.collection('barbershops').doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Barbershop.fromFirestore(doc);
    });
  }

  /// Super Admin Only: Toggle active status (Soft Delete)
  Future<void> setBarbershopActiveStatus(String id, bool isActive) async {
    try {
      await _firestore.collection('barbershops').doc(id).update({
        'isActive': isActive,
        'updated_at': FieldValue.serverTimestamp(),
      });
      // Clear cache to force refresh on next fetch
      _cachedBarbershops = null;
    } catch (e) {
      debugPrint('Error setBarbershopActiveStatus: $e');
      rethrow;
    }
  }

  Future<Barbershop?> getBarbershopById(String barbershopId) async {
    if (barbershopId.isEmpty) return null;
    try {
      final doc = await _firestore
          .collection('barbershops')
          .doc(barbershopId)
          .get();
      if (!doc.exists) return null;
      return Barbershop.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error getBarbershopById: $e');
      return null;
    }
  }

  /// Update special order fee for a barbershop (in smallest currency unit)
  Future<void> updateSpecialOrderFee(String barbershopId, int fee) async {
    try {
      await _firestore.collection('barbershops').doc(barbershopId).update({
        'special_order_fee': fee,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updateSpecialOrderFee: $e');
      rethrow;
    }
  }

  Future<void> updateShopStatus(String id, bool isOpen) async {
    try {
      await _firestore.collection('barbershops').doc(id).update({
        'isOpen': isOpen,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updateShopStatus: $e');
      rethrow;
    }
  }

  // -----------------------
  // BARBERMAN FUNCTIONS
  // -----------------------
  Future<List<Barberman>> getBarbermenByShop(String barbershopId) async {
    try {
      final snapshot = await _firestore
          .collection('barbermen')
          .where('barbershop_id', isEqualTo: barbershopId)
          .get();

      return snapshot.docs.map((doc) => Barberman.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error getBarbermenByShop: $e');
      return [];
    }
  }

  Future<Barberman?> getBarbermanById(String barbermanId) async {
    if (barbermanId.isEmpty) return null;
    try {
      final doc = await _firestore
          .collection('barbermen')
          .doc(barbermanId)
          .get();
      if (!doc.exists) return null;
      return Barberman.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error getBarbermanById: $e');
      return null;
    }
  }

  Future<String> saveService(Service service) async {
    try {
      final data = service.toJson();
      if (service.id.isEmpty) {
        final ref = await _firestore.collection('services').add(data);
        return ref.id;
      } else {
        await _firestore.collection('services').doc(service.id).set(data, SetOptions(merge: true));
        return service.id;
      }
    } catch (e) {
      debugPrint('Error saveService: $e');
      rethrow;
    }
  }

  Future<void> deleteService(String id) async {
    try {
      await _firestore.collection('services').doc(id).delete();
    } catch (e) {
      debugPrint('Error deleteService: $e');
      rethrow;
    }
  }

  Future<void> updateBarbershopSettings(String id, Map<String, dynamic> settings) async {
    try {
      await _firestore.collection('barbershops').doc(id).update({
        ...settings,
        'updated_at': FieldValue.serverTimestamp(),
      });
      // Clear cache after update to ensure UI sees new data
      _cachedBarbershops = null;
    } catch (e) {
      debugPrint('Error updateBarbershopSettings: $e');
      rethrow;
    }
  }

  /// Add a service ID to the barbershop's list
  Future<void> addServiceToBarbershop(String shopId, String serviceId) async {
    try {
      await _firestore.collection('barbershops').doc(shopId).update({
        'services': FieldValue.arrayUnion([serviceId]),
        'updated_at': FieldValue.serverTimestamp(),
      });
      _cachedBarbershops = null;
    } catch (e) {
      debugPrint('Error addServiceToBarbershop: $e');
      rethrow;
    }
  }

  /// Remove a service ID from the barbershop's list
  Future<void> removeServiceFromBarbershop(String shopId, String serviceId) async {
    try {
      await _firestore.collection('barbershops').doc(shopId).update({
        'services': FieldValue.arrayRemove([serviceId]),
        'updated_at': FieldValue.serverTimestamp(),
      });
      _cachedBarbershops = null;
    } catch (e) {
      debugPrint('Error removeServiceFromBarbershop: $e');
      rethrow;
    }
  }

  /// Add an image to the barbershop gallery (Album)
  Future<void> addGalleryImage(String barbershopId, String base64Image) async {
    try {
      await _firestore.collection('barbershops').doc(barbershopId).update({
        'gallery_urls': FieldValue.arrayUnion([base64Image]),
        'updated_at': FieldValue.serverTimestamp(),
      });
      _cachedBarbershops = null;
    } catch (e) {
      debugPrint('Error addGalleryImage: $e');
      rethrow;
    }
  }

  /// Remove an image from the barbershop gallery
  Future<void> removeGalleryImage(String barbershopId, String base64Image) async {
    try {
      await _firestore.collection('barbershops').doc(barbershopId).update({
        'gallery_urls': FieldValue.arrayRemove([base64Image]),
        'updated_at': FieldValue.serverTimestamp(),
      });
      _cachedBarbershops = null;
    } catch (e) {
      debugPrint('Error removeGalleryImage: $e');
      rethrow;
    }
  }

  // -----------------------
  // BARBERMAN CRUD FUNCTIONS
  // -----------------------

  Future<void> saveBarberman(Barberman barber) async {
    try {
      final data = barber.toJson();
      if (barber.id.isEmpty) {
        await _firestore.collection('barbermen').add(data);
      } else {
        await _firestore.collection('barbermen').doc(barber.id).set(data, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error saveBarberman: $e');
      rethrow;
    }
  }

  Future<void> deleteBarberman(String id) async {
    try {
      // We perform a soft-delete by marking as inactive to preserve history
      await _firestore.collection('barbermen').doc(id).update({'isActive': false});
    } catch (e) {
      debugPrint('Error deleteBarberman: $e');
      rethrow;
    }
  }

  Future<void> updateBarbermanLeave(String id, {required bool onLeave, List<String>? specificOffDays}) async {
    try {
      final Map<String, dynamic> update = {'onLeave': onLeave};
      if (specificOffDays != null) update['specificOffDays'] = specificOffDays;
      await _firestore.collection('barbermen').doc(id).update(update);
    } catch (e) {
      debugPrint('Error updateBarbermanLeave: $e');
      rethrow;
    }
  }

  // -----------------------
  // SERVICE FUNCTIONS
  // -----------------------
  Future<List<Service>> getAllServices() async {
    try {
      final snapshot = await _firestore.collection('services').get();
      return snapshot.docs.map((doc) => Service.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error getAllServices: $e');
      return [];
    }
  }

  Future<List<Service>> getServicesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      // Chunking for Firestore limit (max 10 items per 'whereIn')
      List<Service> results = [];
      for (var i = 0; i < ids.length; i += 10) {
        final chunk = ids.sublist(
          i,
          i + 10 > ids.length ? ids.length : i + 10,
        );
        final snapshot = await _firestore
            .collection('services')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        results.addAll(
          snapshot.docs.map((doc) => Service.fromFirestore(doc)),
        );
      }
      return results;
    } catch (e) {
      debugPrint('Error getServicesByIds: $e');
      return [];
    }
  }

  // -----------------------
  // PROMO / BANNER FUNCTIONS
  // -----------------------
  Stream<List<PromoBanner>> getPromoBanners() {
    return _firestore
        .collection('promo_banners')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PromoBanner.fromFirestore(doc))
              .toList(),
        );
  }

  // -----------------------
  // QUEUE / BOOKING FUNCTIONS
  // -----------------------

  /// Stream antrean aktif (booked | ongoing) menggunakan converter ke model Queue
  Stream<List<Queue>> streamActiveQueuesByShop(String barbershopId) {
    return _firestore
        .collection('queues')
        .where('barbershop_id', isEqualTo: barbershopId)
        .where('status', whereIn: ['booked', 'ongoing'])
        .orderBy('booking_time', descending: false)
        .withConverter<Queue>(
          fromFirestore: (snap, _) => Queue.fromFirestore(snap),
          toFirestore: (q, _) => q.toJson(),
        )
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  /// Stream antrean waiting (menunggu konfirmasi) menggunakan converter
  Stream<List<Queue>> streamWaitingQueues(String barbershopId) {
    return _firestore
        .collection('queues')
        .where('barbershop_id', isEqualTo: barbershopId)
        .where('status', isEqualTo: 'waiting')
        .orderBy('booking_time', descending: false)
        .withConverter<Queue>(
          fromFirestore: (snap, _) => Queue.fromFirestore(snap),
          toFirestore: (q, _) => q.toJson(),
        )
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  /// General helper: update status queue (dipakai oleh admin)
  Future<void> updateQueueStatus(
    String queueId,
    String newStatus, {
    Map<String, dynamic>? extra,
  }) async {
    try {
      final payload = <String, dynamic>{
        'status': newStatus,
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (extra != null) payload.addAll(extra);
      await _firestore.collection('queues').doc(queueId).update(payload);
    } catch (e) {
      debugPrint('Error updateQueueStatus: $e');
      rethrow;
    }
  }

  Future<void> cancelQueue(
    String queueId, {
    String reason = 'Cancelled by system/admin',
  }) async {
    try {
      await _firestore.collection('queues').doc(queueId).update({
        'status': 'cancelled',
        'cancellation_reason': reason,
        'cancelled_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error cancelQueue: $e');
      rethrow;
    }
  }

  /// Menandai layanan dimulai (booked -> ongoing)
  Future<void> startService(String queueId) async {
    try {
      await _firestore.collection('queues').doc(queueId).update({
        'status': 'ongoing',
        'start_time': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error startService: $e');
      rethrow;
    }
  }

  /// Menandai layanan selesai (ongoing -> served)
  Future<void> finishService(String queueId) async {
    try {
      final doc = await _firestore.collection('queues').doc(queueId).get();
      if (!doc.exists) throw Exception('Queue not found');

      final data = doc.data()!;
      final start = data['start_time'] as Timestamp?;
      final finishTs = Timestamp.now();

      int actualDuration = 0;
      if (start != null) {
        final now = Timestamp.now();
        actualDuration = ((now.seconds - start.seconds) ~/ 60)
            .clamp(1, 10000)
            .toInt();
      }

      await _firestore.collection('queues').doc(queueId).update({
        'status': 'served',
        'finish_time': finishTs,
        'actual_duration': actualDuration,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error finishService: $e');
      rethrow;
    }
  }

  // -----------------------
  // USER / QUEUE HELPERS
  // -----------------------
  Stream<UserData?> getUserDataStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserData.fromFirestore(doc);
    });
  }

  /// Create queue — default status = 'waiting' (admin harus konfirmasi -> 'booked')
  Future<DocumentReference<Map<String, dynamic>>> createQueue(
    Map<String, dynamic> queueData,
  ) async {
    Timestamp bookingTs;
    final bt = queueData['booking_time'] ?? queueData['bookingTime'];
    if (bt is DateTime) {
      bookingTs = Timestamp.fromDate(bt);
    } else if (bt is Timestamp) {
      bookingTs = bt;
    } else {
      bookingTs = Timestamp.now();
    }

    final Map<String, dynamic> dataToSave = {
      'barbershop_id': queueData['barbershop_id'] ?? queueData['barbershopId'],
      'customer_id': queueData['customer_id'] ?? queueData['customerId'],
      'barberman_id': queueData['barberman_id'] ?? queueData['barbermanId'],
      'service_ids': queueData['service_ids'] ?? queueData['serviceIds'] ?? [],
      'total_price': queueData['total_price'] ?? queueData['totalPrice'],
      'barber_selection_fee':
          queueData['barber_selection_fee'] ??
          queueData['barberSelectionFee'] ??
          0,
      'paid_barber_selection':
          queueData['paid_barber_selection'] ??
          queueData['paidBarberSelection'] ??
          false,
      'estimated_duration':
          queueData['estimated_duration'] ?? queueData['estimatedDuration'],
      'booking_time': bookingTs,
      'status': queueData['status'] ?? 'waiting',
      'created_at': FieldValue.serverTimestamp(),
      'payment_proof_base64':
          queueData['payment_proof_base64'] ?? queueData['payment_proof'],
      'payment_method': queueData['payment_method'],
      'payment_amount': queueData['payment_amount'],
      'order_id': queueData['order_id'],
      'notes': queueData['notes'],
    };

    dataToSave.removeWhere((_, v) => v == null);

    try {
      final ref = await _firestore.collection('queues').add(dataToSave);
      return ref;
    } catch (e) {
      debugPrint('Error createQueue: $e');
      rethrow;
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> getQueuesByOrderId(
    String orderId,
  ) async {
    try {
      return await _firestore
          .collection('queues')
          .where('order_id', isEqualTo: orderId)
          .get();
    } catch (e) {
      debugPrint('Error getQueuesByOrderId: $e');
      rethrow;
    }
  }

  Future<Barberman?> pickDefaultBarber(
    String barbershopId,
    DateTime bookingTime, {
    int? durationMinutes,
    int? lookaheadMinutes, // compatibility alias
  }) async {
    final int duration = durationMinutes ?? lookaheadMinutes ?? 30;
    try {
      final all = await getBarbermenByShop(barbershopId);
      
      // 1. Filter Ketersediaan Dasar (Status & Libur)
      final dateStr = DateFormat('yyyy-MM-dd').format(bookingTime);
      final dayName = DayOfWeek.values[bookingTime.weekday - 1];

      final List<Barberman> candidates = all.where((b) {
        if (!b.isActive) return false;
        if (b.onLeave) return false;
        // Cek Libur Mingguan
        if (b.offDays != null && b.offDays!.contains(dayName)) return false;
        // Cek Libur Spesifik Tanggal
        if (b.specificOffDays.contains(dateStr)) return false;
        return true;
      }).toList();

      if (candidates.isEmpty) return null;

      // 2. Filter Bentrokan Jadwal
      final windowEnd = Timestamp.fromDate(bookingTime.add(Duration(minutes: duration + 15)));

      final List<Barberman> freeBarbers = [];

      for (final b in candidates) {
        final conflictQuery = await _firestore
            .collection('queues')
            .where('barberman_id', isEqualTo: b.id)
            .where('status', whereIn: ['booked', 'ongoing', 'awaiting_payment'])
            .where('booking_time', isGreaterThanOrEqualTo: Timestamp.fromDate(bookingTime.subtract(const Duration(hours: 1))))
            .where('booking_time', isLessThanOrEqualTo: windowEnd)
            .get();

        bool hasConflict = false;
        for (var doc in conflictQuery.docs) {
          final qStart = (doc.data()['booking_time'] as Timestamp).toDate();
          final qDur = doc.data()['estimated_duration'] ?? 30;
          final qEnd = qStart.add(Duration(minutes: qDur + 15));

          if (bookingTime.isBefore(qEnd) && bookingTime.add(Duration(minutes: duration)).isAfter(qStart)) {
            hasConflict = true;
            break;
          }
        }

        if (!hasConflict) freeBarbers.add(b);
      }

      if (freeBarbers.isEmpty) return null;

      // 3. Fairness Algorithm: Pilih yang monthlyHaircutCount paling sedikit
      freeBarbers.sort((a, b) => a.monthlyHaircutCount.compareTo(b.monthlyHaircutCount));

      return freeBarbers.first;
    } catch (e) {
      debugPrint('Error pickDefaultBarber (Fairness): $e');
      return null;
    }
  }

  Future<List<Barbershop>> searchBarbershops(String query) async {
    try {
      debugPrint("🔍 Searching for: '$query'");
      // 1. Get all barbershops (uses cache internally)
      final allShops = await getAllBarbershops();
      debugPrint("🔍 Fetched ${allShops.length} shops (cache/firestore)");

      if (query.trim().isEmpty) {
        // Return only open shops for default list if query is empty
        return allShops.where((s) => s.isOpen).toList();
      }

      final lowerQuery = query.trim().toLowerCase();

      // 2. Filter locally
      final results = allShops.where((shop) {
        final nameMatch = shop.name.toLowerCase().contains(lowerQuery);
        final addressMatch = shop.addres.toLowerCase().contains(lowerQuery);
        final serviceMatch = shop.services.any((s) => s.toLowerCase().contains(lowerQuery));
        
        return nameMatch || addressMatch || serviceMatch;
      }).toList();

      debugPrint("🔍 Found ${results.length} results matching '$query'");
      return results;
    } catch (e) {
      debugPrint('❌ Error searchBarbershops: $e');
      return [];
    }
  }

  // -----------------------
  // FAVORITE FUNCTIONS
  // -----------------------

  /// Toggle barbershop as favorite for a user.
  /// Uses an array union/remove for atomicity.
  Future<void> toggleFavorite(String userId, String barbershopId) async {
    if (userId.isEmpty || barbershopId.isEmpty) return;
    try {
      final userRef = _firestore.collection('users').doc(userId);
      final doc = await userRef.get();

      if (!doc.exists) {
        // Create user doc if not exists
        await userRef.set({
          'favorite_barbershops': [barbershopId],
          'updated_at': FieldValue.serverTimestamp(),
        });
        return;
      }

      final data = doc.data() as Map<String, dynamic>;
      final List<String> favorites = List<String>.from(
        (data['favorite_barbershops'] ?? []) as List,
      );

      if (favorites.contains(barbershopId)) {
        // Remove from favorites
        await userRef.update({
          'favorite_barbershops': FieldValue.arrayRemove([barbershopId]),
          'updated_at': FieldValue.serverTimestamp(),
        });
      } else {
        // Add to favorites
        await userRef.update({
          'favorite_barbershops': FieldValue.arrayUnion([barbershopId]),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error toggleFavorite: $e');
      rethrow;
    }
  }

  /// Check if a barbershop is in user's favorites
  Future<bool> isFavorite(String userId, String barbershopId) async {
    if (userId.isEmpty || barbershopId.isEmpty) return false;
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return false;

      final data = doc.data() as Map<String, dynamic>;
      final List<String> favorites = List<String>.from(
        (data['favorite_barbershops'] ?? []) as List,
      );
      return favorites.contains(barbershopId);
    } catch (e) {
      debugPrint('Error isFavorite: $e');
      return false;
    }
  }

  /// Stream of user's favorite barbershop IDs
  Stream<List<String>> streamFavoriteIds(String userId) {
    if (userId.isEmpty) return Stream.value([]);
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return [];
      final data = doc.data() as Map<String, dynamic>;
      final List<dynamic> favs = data['favorite_barbershops'] ?? [];
      return favs.map((e) => e.toString()).toList();
    });
  }

  /// Get list of favorite Barbershop objects
  Future<List<Barbershop>> getFavoriteBarbershops(String userId) async {
    if (userId.isEmpty) return [];
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return [];

      final data = doc.data() as Map<String, dynamic>;
      final List<dynamic> favs = data['favorite_barbershops'] ?? [];
      final List<String> favoriteIds = favs.map((e) => e.toString()).toList();

      if (favoriteIds.isEmpty) return [];

      // Fetch barbershops in chunks of 10 (Firestore limit for 'whereIn')
      List<Barbershop> results = [];
      for (var i = 0; i < favoriteIds.length; i += 10) {
        final chunk = favoriteIds.sublist(
          i,
          i + 10 > favoriteIds.length ? favoriteIds.length : i + 10,
        );
        final snapshot = await _firestore
            .collection('barbershops')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        results.addAll(
          snapshot.docs.map((doc) => Barbershop.fromFirestore(doc)),
        );
      }
      return results;
    } catch (e) {
      debugPrint('Error getFavoriteBarbershops: $e');
      return [];
    }
  }
}
