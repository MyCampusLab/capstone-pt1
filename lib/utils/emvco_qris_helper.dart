// lib/utils/emvco_qris_helper.dart

class EmvcoTlvNode {
  final String tag;
  final int length;
  final String value;

  const EmvcoTlvNode({
    required this.tag,
    required this.length,
    required this.value,
  });
}

/// Utilitas murni Dart untuk validasi dan konversi EMVCo QRIS Statis ke Dinamis
/// (Standar Nasional QRIS Bank Indonesia: Tag 01=12, Tag 54=Nominal Unik, Tag 63=CRC16-CCITT).
class EmvcoQrisHelper {
  /// Menghitung CRC16-CCITT (initial = 0xFFFF, polynomial = 0x1021, non-reflected)
  static String computeCrc16Ccitt(String payloadWithoutCrcValue) {
    int crc = 0xFFFF;
    for (int i = 0; i < payloadWithoutCrcValue.length; i++) {
      crc ^= (payloadWithoutCrcValue.codeUnitAt(i) & 0xFF) << 8;
      for (int bit = 0; bit < 8; bit++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }

  /// Membuat payload QRIS Statis standar EMVCo Indonesia yang valid CRC16-nya.
  static String buildValidStaticQris({
    required String nmid,
    required String merchantName,
    required String merchantCity,
    String postalCode = '52181',
  }) {
    final cleanName = merchantName.length > 25
        ? merchantName.substring(0, 25).toUpperCase()
        : merchantName.toUpperCase();
    final cleanCity = merchantCity.length > 15
        ? merchantCity.substring(0, 15).toUpperCase()
        : merchantCity.toUpperCase();
    final cleanPostal =
        postalCode.length > 10 ? postalCode.substring(0, 10) : postalCode;

    final gui = '0014ID.CO.QRIS.WWW';
    final nmidTag =
        '02${nmid.length.toString().padLeft(2, '0')}$nmid';
    const criteria = '0303UMI';
    final tag51Val = '$gui$nmidTag$criteria';

    final nodes = <EmvcoTlvNode>[
      const EmvcoTlvNode(tag: '00', length: 2, value: '01'),
      const EmvcoTlvNode(tag: '01', length: 2, value: '11'),
      EmvcoTlvNode(tag: '51', length: tag51Val.length, value: tag51Val),
      const EmvcoTlvNode(tag: '52', length: 4, value: '7230'),
      const EmvcoTlvNode(tag: '53', length: 3, value: '360'),
      const EmvcoTlvNode(tag: '58', length: 2, value: 'ID'),
      EmvcoTlvNode(tag: '59', length: cleanName.length, value: cleanName),
      EmvcoTlvNode(tag: '60', length: cleanCity.length, value: cleanCity),
      EmvcoTlvNode(tag: '61', length: cleanPostal.length, value: cleanPostal),
    ];

    return serializeTlvNodesWithCrc(nodes);
  }

  static final String defaultSampleStaticQris = buildValidStaticQris(
    nmid: 'ID1025000001001',
    merchantName: 'FEBRIAN BARBERSHOP',
    merchantCity: 'TEGAL',
    postalCode: '52181',
  );

  /// Mem-parse string EMVCo menjadi daftar node TLV top-level.
  static List<EmvcoTlvNode> parseTlvNodes(String qrisPayload) {
    final nodes = <EmvcoTlvNode>[];
    int idx = 0;

    while (idx < qrisPayload.length) {
      if (idx + 4 > qrisPayload.length) {
        throw FormatException(
            'Format TLV QRIS rusak pada indeks $idx: header tag/length tidak utuh.');
      }
      final tag = qrisPayload.substring(idx, idx + 2);
      final lenStr = qrisPayload.substring(idx + 2, idx + 4);
      final length = int.tryParse(lenStr);
      if (length == null || length < 0) {
        throw FormatException('Panjang TLV tidak valid untuk tag $tag: "$lenStr".');
      }
      final valueStart = idx + 4;
      final valueEnd = valueStart + length;
      if (valueEnd > qrisPayload.length) {
        throw FormatException(
            'Nilai TLV untuk tag $tag melebihi panjang string QRIS ($valueEnd > ${qrisPayload.length}).');
      }
      final value = qrisPayload.substring(valueStart, valueEnd);
      nodes.add(EmvcoTlvNode(tag: tag, length: length, value: value));
      idx = valueEnd;
    }

    return nodes;
  }

  /// Merangkai kembali node TLV dan menambahkan Tag 6304 beserta nilai CRC16-CCITT.
  static String serializeTlvNodesWithCrc(List<EmvcoTlvNode> nodesWithoutCrc) {
    final buffer = StringBuffer();
    for (final n in nodesWithoutCrc) {
      if (n.tag == '63') continue;
      final lenStr = n.value.length.toString().padLeft(2, '0');
      buffer.write('${n.tag}$lenStr${n.value}');
    }
    buffer.write('6304');
    final bodyWith6304 = buffer.toString();
    final crc = computeCrc16Ccitt(bodyWith6304);
    return '$bodyWith6304$crc';
  }

  /// Memvalidasi apakah string QRIS statis merupakan format EMVCo Indonesia yang sah dan ber-CRC16 tepat.
  static String? validateStaticQris(String? rawQris) {
    final trimmed = (rawQris ?? '').trim();
    if (trimmed.isEmpty) {
      return 'Payload QRIS tidak boleh kosong.';
    }
    if (trimmed.length < 24) {
      return 'Payload QRIS terlalu pendek (< 24 karakter).';
    }
    if (!trimmed.startsWith('000201')) {
      return 'Payload QRIS wajib diawali "000201".';
    }
    final crcTagPos = trimmed.length - 8;
    if (trimmed.substring(crcTagPos, crcTagPos + 4) != '6304') {
      return 'Tag CRC "6304" tidak ditemukan pada 8 karakter terakhir.';
    }

    List<EmvcoTlvNode> nodes;
    try {
      nodes = parseTlvNodes(trimmed);
    } catch (e) {
      return e.toString();
    }

    final hasCountryId = nodes.any((n) => n.tag == '58' && n.value == 'ID');
    if (!hasCountryId) {
      return 'Tag Negara "5802ID" tidak ditemukan dalam payload QRIS.';
    }

    final hasCurrencyIdr = nodes.any((n) => n.tag == '53' && n.value == '360');
    if (!hasCurrencyIdr) {
      return 'Tag Mata Uang Rupiah "5303360" tidak ditemukan.';
    }

    final payloadWithoutCrc = trimmed.substring(0, trimmed.length - 4);
    final actualCrc = trimmed.substring(trimmed.length - 4).toUpperCase();
    final expectedCrc = computeCrc16Ccitt(payloadWithoutCrc);
    if (actualCrc != expectedCrc) {
      return 'Checksum CRC16 tidak cocok (tertera: $actualCrc, seharusnya: $expectedCrc).';
    }

    return null; // Valid
  }

  /// Mengonversi QRIS Statis menjadi QRIS Dinamis dengan menyuntikkan Tag 54 (Nominal Unik)
  /// dan menghitung ulang Checksum CRC16-CCITT (Tag 6304).
  static String generateDynamicQris(String staticQris, int exactAmountRupiah) {
    final err = validateStaticQris(staticQris);
    if (err != null) {
      throw FormatException('QRIS Statis tidak valid: $err');
    }
    if (exactAmountRupiah < 1) {
      throw ArgumentError('Nominal QRIS dinamis harus >= Rp 1.');
    }

    final amountStr = exactAmountRupiah.toString();
    final rawNodes = parseTlvNodes(staticQris.trim())
        .where((n) => n.tag != '63' && n.tag != '54')
        .toList();

    final tag01Idx = rawNodes.indexWhere((n) => n.tag == '01');
    if (tag01Idx >= 0) {
      rawNodes[tag01Idx] = const EmvcoTlvNode(tag: '01', length: 2, value: '12');
    } else {
      rawNodes.insert(1, const EmvcoTlvNode(tag: '01', length: 2, value: '12'));
    }

    final tag54Node = EmvcoTlvNode(
      tag: '54',
      length: amountStr.length,
      value: amountStr,
    );

    final tag58Idx = rawNodes.indexWhere((n) => n.tag == '58');
    if (tag58Idx >= 0) {
      rawNodes.insert(tag58Idx, tag54Node);
    } else {
      rawNodes.add(tag54Node);
    }

    return serializeTlvNodesWithCrc(rawNodes);
  }

  /// Menghasilkan kode unik deterministik (1..50) dari orderId jika belum dialokasikan dari server.
  static int deriveDeterministicUniqueCode(String seedId) {
    if (seedId.trim().isEmpty) return 1;
    int hash = 0;
    for (int i = 0; i < seedId.length; i++) {
      hash = ((hash * 31) + seedId.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return (hash % 50) + 1;
  }
}
