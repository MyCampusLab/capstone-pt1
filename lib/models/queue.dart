import 'package:cloud_firestore/cloud_firestore.dart';

enum QueueStatus { 
  waiting, 
  awaitingPayment, // Approved by admin, waiting for customer payment
  booked, 
  ongoing, 
  served, 
  cancelled, 
  cancellationRequested 
}

enum RequestStatus { pending, approved, rejected }

extension QueueStatusExtension on QueueStatus {
  String get value {
    switch (this) {
      case QueueStatus.waiting: return 'waiting';
      case QueueStatus.awaitingPayment: return 'awaiting_payment';
      case QueueStatus.booked: return 'booked';
      case QueueStatus.ongoing: return 'ongoing';
      case QueueStatus.served: return 'served';
      case QueueStatus.cancelled: return 'cancelled';
      case QueueStatus.cancellationRequested: return 'cancellation_requested';
    }
  }

  static QueueStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'booked':
      case 'paid_verified':
      case 'payment_confirmed':
      case 'confirmed':
        return QueueStatus.booked;
      case 'awaiting_payment':
      case 'payment_pending':
        return QueueStatus.awaitingPayment;
      case 'waiting':
      case 'created':
        return QueueStatus.waiting;
      case 'ongoing': return QueueStatus.ongoing;
      case 'served': return QueueStatus.served;
      case 'cancelled':
      case 'refund_completed':
        return QueueStatus.cancelled;
      case 'cancellation_requested': return QueueStatus.cancellationRequested;
      default: return QueueStatus.waiting;
    }
  }
}

extension RequestStatusExtension on RequestStatus {
  String get value {
    switch (this) {
      case RequestStatus.pending: return 'pending';
      case RequestStatus.approved: return 'approved';
      case RequestStatus.rejected: return 'rejected';
    }
  }

  static RequestStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return RequestStatus.approved;
      case 'rejected': return RequestStatus.rejected;
      default: return RequestStatus.pending;
    }
  }
}

class Queue {
  final String id;
  final String barbershopId;
  final String customerId;
  final String barbermanId;
  final Timestamp bookingTime;
  final Timestamp? startTime;
  final Timestamp? finishTime;
  final int? actualDuration;
  final int? estimatedDuration;
  final List<String>? serviceIds;
  final String? serviceId;
  final int? totalPrice;
  final int? barberSelectionFee;
  final bool? paidBarberSelection;
  final bool isAutoAssigned; // New
  final QueueStatus status;
  final RequestStatus requestStatus;
  final Timestamp? paymentDeadline;
  final String? paymentMethod;
  final String? rejectionReason;
  final String? verifiedBy;
  final String? cancellationReason; // New field
  final Timestamp? createdAt;
  final String? paymentProofBase64;
  final String? paymentProofUrl;
  final bool? isRefunded;
  final Timestamp? refundedAt;
  final String? refundReason;
  final String? refundedBy;
  final String? refundProofBase64;
  final String? customerName; // New: For manual booking display
  final String? orderId; // New: For order tracking
  final Map<String, String>? serviceNotes; // New: Notes per service
  final int? uniqueCode;
  final int? expectedAmount;
  final String? qrisDynamicPayload;
  final String? paymentAppSource;
  final String? dompetkuTxId;
  Queue({
    required this.id,
    required this.barbershopId,
    required this.customerId,
    required this.barbermanId,
    required this.bookingTime,
    this.startTime,
    this.finishTime,
    this.actualDuration,
    this.estimatedDuration,
    this.serviceIds,
    this.serviceId,
    this.totalPrice,
    this.barberSelectionFee,
    this.paidBarberSelection,
    this.isAutoAssigned = false,
    required this.status,
    required this.requestStatus,
    this.paymentDeadline,
    this.paymentMethod,
    this.rejectionReason,
    this.verifiedBy,
    this.cancellationReason,
    this.createdAt,
    this.paymentProofBase64,
    this.paymentProofUrl,
    this.isRefunded,
    this.refundedAt,
    this.refundReason,
    this.refundedBy,
    this.refundProofBase64,
    this.customerName,
    this.orderId,
    this.serviceNotes,
    this.uniqueCode,
    this.expectedAmount,
    this.qrisDynamicPayload,
    this.paymentAppSource,
    this.dompetkuTxId,
  });

  String? get firstServiceId {
    if (serviceIds != null && serviceIds!.isNotEmpty) return serviceIds!.first;
    return serviceId;
  }

  factory Queue.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    String? readString(dynamic v) => (v == null || v.toString().isEmpty) ? null : v.toString();
    List<String>? readStringList(dynamic v) {
      if (v == null) return null;
      if (v is List) return v.map((e) => e.toString()).toList();
      return null;
    }

    return Queue(
      id: doc.id,
      barbershopId: data['barbershop_id'] ?? data['barbershopId'] ?? '',
      customerId: data['customer_id'] ?? data['customerId'] ?? '',
      barbermanId: data['barberman_id'] ?? data['barbermanId'] ?? '',
      bookingTime: (data['booking_time'] ?? data['bookingTime']) as Timestamp? ?? Timestamp.now(),
      startTime: (data['start_time'] ?? data['startTime']) as Timestamp?,
      finishTime: (data['finish_time'] ?? data['finishTime']) as Timestamp?,
      actualDuration: (data['actual_duration'] ?? data['actualDuration'])?.toInt(),
      estimatedDuration: (data['estimated_duration'] ?? data['estimatedDuration'])?.toInt(),
      serviceIds: readStringList(data['service_ids'] ?? data['serviceIds']),
      serviceId: readString(data['service_id'] ?? data['serviceId']),
      totalPrice: (data['total_price'] ?? data['totalPrice'])?.toInt(),
      barberSelectionFee: (data['barber_selection_fee'] ?? data['barberSelectionFee'])?.toInt(),
      paidBarberSelection: data['paid_barber_selection'] ?? data['paidBarberSelection'] ?? false,
      isAutoAssigned: data['is_auto_assigned'] ?? data['isAutoAssigned'] ?? false,
      status: QueueStatusExtension.fromString(data['status']?.toString() ?? 'waiting'),
      requestStatus: RequestStatusExtension.fromString(data['request_status'] ?? data['requestStatus'] ?? 'pending'),
      paymentDeadline: (data['payment_deadline'] ?? data['paymentDeadline']) as Timestamp?,
      paymentMethod: readString(data['payment_method'] ?? data['paymentMethod']),
      rejectionReason: readString(data['rejection_reason'] ?? data['rejectionReason']),
      verifiedBy: readString(data['verified_by'] ?? data['verifiedBy']),
      cancellationReason: readString(data['cancellation_reason'] ?? data['cancellationReason']),
      createdAt: (data['created_at'] ?? data['createdAt']) as Timestamp?,
      paymentProofBase64: readString(data['payment_proof_base64'] ?? data['paymentProofBase64']),
      paymentProofUrl: readString((data['payment'] is Map) ? (data['payment']['proofUrl'] ?? data['payment']['proof_url']) : data['payment_proof_url']),
      isRefunded: data['is_refunded'] ?? data['isRefunded'] ?? false,
      refundedAt: (data['refunded_at'] ?? data['refundedAt']) as Timestamp?,
      refundReason: readString(data['refund_reason'] ?? data['refundReason']),
      refundedBy: readString(data['refunded_by'] ?? data['refundedBy']),
      refundProofBase64: readString(data['refund_proof_base64'] ?? data['refundProofBase64']),
      customerName: readString(data['customer_name'] ?? data['customerName']),
      orderId: data['order_id'] ?? data['orderId'],
      serviceNotes: (data['service_notes'] as Map<String, dynamic>?)?.map((key, value) => MapEntry(key, value.toString())),
      uniqueCode: (data['unique_code'] ?? data['uniqueCode'])?.toInt(),
      expectedAmount: (data['expected_amount'] ?? data['expectedAmount'])?.toInt(),
      qrisDynamicPayload: readString(data['qris_dynamic_payload'] ?? data['qrisDynamicPayload']),
      paymentAppSource: readString(data['payment_app_source'] ?? data['paymentAppSource']),
      dompetkuTxId: readString(data['dompetku_tx_id'] ?? data['dompetkuTxId']),
    );
  }

  Map<String, dynamic> toJson() {
    final data = {
      'barbershop_id': barbershopId,
      'customer_id': customerId,
      'barberman_id': barbermanId,
      'booking_time': bookingTime,
      'start_time': startTime,
      'finish_time': finishTime,
      'actual_duration': actualDuration,
      'estimated_duration': estimatedDuration,
      'service_ids': serviceIds,
      'service_id': serviceId,
      'total_price': totalPrice,
      'barber_selection_fee': barberSelectionFee,
      'paid_barber_selection': paidBarberSelection,
      'is_auto_assigned': isAutoAssigned,
      'status': status.value,
      'request_status': requestStatus.value,
      'payment_deadline': paymentDeadline,
      'payment_method': paymentMethod,
      'rejection_reason': rejectionReason,
      'verified_by': verifiedBy,
      'cancellation_reason': cancellationReason,
      'created_at': createdAt ?? FieldValue.serverTimestamp(),
      'payment_proof_base64': paymentProofBase64,
      'is_refunded': isRefunded ?? false,
      'refunded_at': refundedAt,
      'refund_reason': refundReason,
      'refunded_by': refundedBy,
      'refund_proof_base64': refundProofBase64,
      'customer_name': customerName,
      'order_id': orderId,
      'service_notes': serviceNotes,
      'unique_code': uniqueCode,
      'expected_amount': expectedAmount,
      'qris_dynamic_payload': qrisDynamicPayload,
      'payment_app_source': paymentAppSource,
      'dompetku_tx_id': dompetkuTxId,
    };
    data.removeWhere((_, v) => v == null);
    return data;
  }

  Queue copyWith({
    String? id,
    String? barbershopId,
    String? customerId,
    String? barbermanId,
    Timestamp? bookingTime,
    Timestamp? startTime,
    Timestamp? finishTime,
    int? actualDuration,
    int? estimatedDuration,
    List<String>? serviceIds,
    String? serviceId,
    int? totalPrice,
    int? barberSelectionFee,
    bool? paidBarberSelection,
    bool? isAutoAssigned,
    QueueStatus? status,
    RequestStatus? requestStatus,
    Timestamp? paymentDeadline,
    String? paymentMethod,
    String? rejectionReason,
    String? verifiedBy,
    String? cancellationReason,
    Timestamp? createdAt,
    String? paymentProofBase64,
    String? paymentProofUrl,
    bool? isRefunded,
    Timestamp? refundedAt,
    String? refundReason,
    String? refundedBy,
    String? refundProofBase64,
    String? customerName,
    String? orderId,
    Map<String, String>? serviceNotes,
    int? uniqueCode,
    int? expectedAmount,
    String? qrisDynamicPayload,
    String? paymentAppSource,
    String? dompetkuTxId,
  }) {
    return Queue(
      id: id ?? this.id,
      barbershopId: barbershopId ?? this.barbershopId,
      customerId: customerId ?? this.customerId,
      barbermanId: barbermanId ?? this.barbermanId,
      bookingTime: bookingTime ?? this.bookingTime,
      startTime: startTime ?? this.startTime,
      finishTime: finishTime ?? this.finishTime,
      actualDuration: actualDuration ?? this.actualDuration,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      serviceIds: serviceIds ?? this.serviceIds,
      serviceId: serviceId ?? this.serviceId,
      totalPrice: totalPrice ?? this.totalPrice,
      barberSelectionFee: barberSelectionFee ?? this.barberSelectionFee,
      paidBarberSelection: paidBarberSelection ?? this.paidBarberSelection,
      isAutoAssigned: isAutoAssigned ?? this.isAutoAssigned,
      status: status ?? this.status,
      requestStatus: requestStatus ?? this.requestStatus,
      paymentDeadline: paymentDeadline ?? this.paymentDeadline,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      createdAt: createdAt ?? this.createdAt,
      paymentProofBase64: paymentProofBase64 ?? this.paymentProofBase64,
      paymentProofUrl: paymentProofUrl ?? this.paymentProofUrl,
      isRefunded: isRefunded ?? this.isRefunded,
      refundedAt: refundedAt ?? this.refundedAt,
      refundReason: refundReason ?? this.refundReason,
      refundedBy: refundedBy ?? this.refundedBy,
      refundProofBase64: refundProofBase64 ?? this.refundProofBase64,
      customerName: customerName ?? this.customerName,
      orderId: orderId ?? this.orderId,
      serviceNotes: serviceNotes ?? this.serviceNotes,
      uniqueCode: uniqueCode ?? this.uniqueCode,
      expectedAmount: expectedAmount ?? this.expectedAmount,
      qrisDynamicPayload: qrisDynamicPayload ?? this.qrisDynamicPayload,
      paymentAppSource: paymentAppSource ?? this.paymentAppSource,
      dompetkuTxId: dompetkuTxId ?? this.dompetkuTxId,
    );
  }
}