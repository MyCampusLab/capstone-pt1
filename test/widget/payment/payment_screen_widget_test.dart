import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geges_smartbarber/screens/customer/payment_screen.dart';
import 'package:geges_smartbarber/models/queue.dart';
import 'package:geges_smartbarber/services/queue_service_contract.dart';
import '../../helpers/test_helpers.dart';

class FakeQueueService implements QueueServiceContract {
  final Queue? byId;
  final Queue? byResolve;
  bool submitCalled = false;

  FakeQueueService({this.byId, this.byResolve});
  @override
  Future<dynamic> createQueue(Map<String, dynamic> queueData) async => null;

  @override
  Future<Queue?> getQueueById(String id) async => byId;

  @override
  Stream<Queue?> streamQueueById(String id) async* {
    yield byId;
  }

  @override
  Future<Queue?> resolveQueueForCustomerByIdOrOrder(
    String idOrOrderId,
    String customerId,
  ) async => byResolve;

  @override
  Future<void> submitPaymentProofForQueue({
    required String queueId,
    required String userId,
    required String base64Proof,
  }) async {
    submitCalled = true;
  }

  @override
  Future<void> cancelQueue(
    String queueId, {
    String reason = 'Admin/Barberman Cancellation',
    String? cancelledBy,
  }) async {}

  @override
  Future<int> cancelExpiredAwaitingPaymentQueuesForCustomer(
    String customerId,
  ) async => 0;

  @override
  Future<int> cancelExpiredWaitingQueuesForCustomer(
    String customerId,
  ) async => 0;
}

void main() {
  testWidgets('PaymentScreen shows uploaded state and disables submit', (
    WidgetTester tester,
  ) async {
    final q = Queue(
      id: 'q-1',
      barbershopId: 'shop-1',
      customerId: 'user1',
      barbermanId: '',
      bookingTime: Timestamp.now(),
      status: QueueStatus.awaitingPayment,
      requestStatus: RequestStatus.approved,
      paymentDeadline: Timestamp.fromDate(
        DateTime.now().add(const Duration(minutes: 10)),
      ),
      paymentProofBase64: 'exists',
    );

    final fake = FakeQueueService(byId: q, byResolve: q);

    await tester.pumpWidget(
      wrapWithLocalization(PaymentScreen(
          orderId: 'order-1',
          totalPrice: 50000,
          queueService: fake,
          testUserId: 'user1',
        ),
      ),
    );
    
    // Wait for stream to deliver data
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify UI shows "Sedang Diverifikasi" (Banner)
    expect(find.text('Sedang Diverifikasi'), findsOneWidget);
    
    // Button text is now "Menunggu Verifikasi Admin" (verificationPending localized)
    expect(find.text('Menunggu Verifikasi Admin'), findsOneWidget);

    // Verify button is present and disabled
    final btnFinder = find.widgetWithText(ElevatedButton, 'Menunggu Verifikasi Admin');
    expect(btnFinder, findsOneWidget);
    
    final btn = tester.widget<ElevatedButton>(btnFinder);
    expect(btn.onPressed, isNull);
  });
}
