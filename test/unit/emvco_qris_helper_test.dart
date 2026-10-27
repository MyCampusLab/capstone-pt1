import 'package:flutter_test/flutter_test.dart';
import 'package:geges_smartbarber/utils/emvco_qris_helper.dart';
import 'package:qr/qr.dart';

void main() {
  group('EmvcoQrisHelper — Validasi & Konversi QRIS Statis ke Dinamis', () {
    test('buildValidStaticQris menghasilkan payload QRIS Statis ber-CRC16 valid', () {
      final staticQris = EmvcoQrisHelper.buildValidStaticQris(
        nmid: 'ID1025000001001',
        merchantName: 'FEBRIAN BARBERSHOP',
        merchantCity: 'TEGAL',
        postalCode: '52181',
      );

      expect(staticQris.startsWith('000201010211'), isTrue);
      expect(EmvcoQrisHelper.validateStaticQris(staticQris), isNull);
    });

    test('generateDynamicQris mengubah Tag 01 menjadi 12, menyisipkan Tag 54, dan memperbarui CRC16', () {
      final staticQris = EmvcoQrisHelper.defaultSampleStaticQris;
      final dynamicQris = EmvcoQrisHelper.generateDynamicQris(staticQris, 40017);

      expect(dynamicQris.startsWith('000201010212'), isTrue);
      expect(dynamicQris.contains('5405400175802ID'), isTrue);
      expect(EmvcoQrisHelper.validateStaticQris(dynamicQris), isNull);

      final nodes = EmvcoQrisHelper.parseTlvNodes(dynamicQris);
      final tag01 = nodes.firstWhere((n) => n.tag == '01');
      final tag54 = nodes.firstWhere((n) => n.tag == '54');
      expect(tag01.value, equals('12'));
      expect(tag54.value, equals('40017'));
    });

    test('validateStaticQris menolak payload dengan checksum CRC16 yang dimanipulasi', () {
      final valid = EmvcoQrisHelper.defaultSampleStaticQris;
      final tampered = '${valid.substring(0, valid.length - 4)}0000';
      expect(EmvcoQrisHelper.validateStaticQris(tampered), isNotNull);
    });

    test('deriveDeterministicUniqueCode selalu menghasilkan angka dalam rentang 1..50', () {
      for (int i = 1; i <= 100; i++) {
        final code = EmvcoQrisHelper.deriveDeterministicUniqueCode('order-$i');
        expect(code, greaterThanOrEqualTo(1));
        expect(code, lessThanOrEqualTo(50));
      }
    });

    test('payload QRIS dinamis menghasilkan matriks ISO/IEC 18004 Reed-Solomon QR valid', () {
      final dynamicQris = EmvcoQrisHelper.generateDynamicQris(
        EmvcoQrisHelper.defaultSampleStaticQris,
        40017,
      );
      final qrCode = QrCode(
        payload: QrPayload.fromString(dynamicQris),
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      );
      final qrImage = QrImage(qrCode);
      expect(qrImage.moduleCount, greaterThanOrEqualTo(29));
      // Sudut finder pattern (0,0), (0,6), (6,0), dan titik tengah (3,3) wajib gelap (dark)
      expect(qrImage.isDark(0, 0), isTrue);
      expect(qrImage.isDark(0, 6), isTrue);
      expect(qrImage.isDark(6, 0), isTrue);
      expect(qrImage.isDark(3, 3), isTrue);
    });
  });
}
