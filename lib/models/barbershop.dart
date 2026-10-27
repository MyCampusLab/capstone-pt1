import 'package:cloud_firestore/cloud_firestore.dart';

class Barbershop {
  final String id;
  final String name;
  final String addres;
  final String? googleMapsUrl; // Link ke Google Maps
  final String imageUrl; // Utama
  final List<String> services;
  final List<String> facilities; // Fasilitas (AC, Wifi, etc)
  final List<String> galleryUrls; // Album (Base64)
  final int openHour;
  final int closeHour;
  final int? paymentWindowMinutes;
  final int? specialOrderFee;
  final int barberSelectionFee; 
  final bool isOpen;
  final bool isActive; // Status aktif sistem (Super Admin Control)
  final List<int> weeklyHolidays; 
  final List<String> specificHolidays; 
  
  // Social Media
  final String? instagramUrl;
  final String? whatsappNumber;
  final String? tiktokUrl;
  final String? facebookUrl;
  final String? twitterUrl;
  final String? qrisRawPayload;
  final String? dompetkuWebhookUrl;
  Barbershop({
    required this.id,
    required this.name,
    required this.addres,
    this.googleMapsUrl,
    required this.imageUrl,
    required this.services,
    this.facilities = const [],
    this.galleryUrls = const [],
    required this.openHour,
    required this.closeHour,
    this.paymentWindowMinutes,
    this.specialOrderFee,
    this.barberSelectionFee = 5000,
    required this.isOpen,
    this.isActive = true, // Default true agar data lama tetap muncul
    this.weeklyHolidays = const [],
    this.specificHolidays = const [],
    this.instagramUrl,
    this.whatsappNumber,
    this.tiktokUrl,
    this.facebookUrl,
    this.twitterUrl,
    this.qrisRawPayload,
    this.dompetkuWebhookUrl,
  });

  factory Barbershop.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    int parseHour(dynamic value, int fallback) {
      if (value == null) return fallback;
      if (value is int) return value;
      if (value is String) {
        if (value.contains(':')) return int.tryParse(value.split(':').first) ?? fallback;
        return int.tryParse(value) ?? fallback;
      }
      return fallback;
    }

    return Barbershop(
      id: doc.id,
      name: data['name'] ?? 'Nama Barbershop',
      addres: (data['address'] ?? data['addres'] ?? 'Alamat Tidak Diketahui') as String,
      googleMapsUrl: data['google_maps_url'],
      imageUrl: data['imageUrl'] ?? 'https://cdn-icons-png.flaticon.com/512/706/706830.png',
      services: List<String>.from(data['services'] ?? []),
      facilities: List<String>.from(data['facilities'] ?? []),
      galleryUrls: List<String>.from(data['gallery_urls'] ?? data['galleryUrls'] ?? []),
      openHour: parseHour(data['open_hour'] ?? data['openHour'], 9),
      closeHour: parseHour(data['close_hour'] ?? data['closeHour'], 21),
      paymentWindowMinutes: (data['payment_window_minutes'] ?? data['paymentWindowMinutes'])?.toInt(),
      specialOrderFee: (data['special_order_fee'] ?? data['specialOrderFee'])?.toInt(),
      barberSelectionFee: (data['barber_selection_fee'] ?? data['barberSelectionFee'])?.toInt() ?? 5000,
      isOpen: data['isOpen'] as bool? ?? false,
      isActive: data['isActive'] as bool? ?? true, // Fallback ke true
      weeklyHolidays: List<int>.from(data['weekly_holidays'] ?? data['weeklyHolidays'] ?? []),
      specificHolidays: List<String>.from(data['specific_holidays'] ?? data['specific_holidays'] ?? []),
      instagramUrl: data['instagram_url'],
      whatsappNumber: data['whatsapp_number'],
      tiktokUrl: data['tiktok_url'],
      facebookUrl: data['facebook_url'],
      twitterUrl: data['twitter_url'],
      qrisRawPayload: data['qris_raw_payload'] ?? data['qrisRawPayload'],
      dompetkuWebhookUrl: data['dompetku_webhook_url'] ?? data['dompetkuWebhookUrl'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'address': addres, // Standardize to 'address' for new writes
      'google_maps_url': googleMapsUrl,
      'imageUrl': imageUrl,
      'services': services,
      'facilities': facilities,
      'gallery_urls': galleryUrls,
      'open_hour': openHour,
      'close_hour': closeHour,
      'payment_window_minutes': paymentWindowMinutes,
      'special_order_fee': specialOrderFee,
      'barber_selection_fee': barberSelectionFee,
      'isOpen': isOpen,
      'isActive': isActive,
      'weekly_holidays': weeklyHolidays,
      'specific_holidays': specificHolidays,
      'instagram_url': instagramUrl,
      'whatsapp_number': whatsappNumber,
      'tiktok_url': tiktokUrl,
      'facebook_url': facebookUrl,
      'twitter_url': twitterUrl,
      'qris_raw_payload': qrisRawPayload,
      'dompetku_webhook_url': dompetkuWebhookUrl,
    };
  }
}
