/**
 * Mesin Konversi EMVCo QRIS Statis ke Dinamis (Standar Bank Indonesia)
 * Mengubah Tag 01 (11 -> 12), menyuntikkan Tag 54 (Nominal Unik),
 * dan menghitung ulang Checksum Tag 63 (CRC16-CCITT 0xFFFF, polynomial 0x1021).
 */

export interface TlvNode {
  tag: string;
  length: number;
  value: string;
}

/**
 * Menghitung CRC16-CCITT (initial = 0xFFFF, polynomial = 0x1021, non-reflected)
 * sesuai spesifikasi EMVCo QR Code.
 */
export function computeCrc16Ccitt(payloadWithoutCrcValue: string): string {
  let crc = 0xffff;
  for (let i = 0; i < payloadWithoutCrcValue.length; i++) {
    crc ^= payloadWithoutCrcValue.charCodeAt(i) << 8;
    for (let bit = 0; bit < 8; bit++) {
      if ((crc & 0x8000) !== 0) {
        crc = ((crc << 1) ^ 0x1021) & 0xffff;
      } else {
        crc = (crc << 1) & 0xffff;
      }
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}

/**
 * Mem-parsing string EMVCo (tanpa atau dengan Tag 63) menjadi array node TLV top-level.
 */
export function parseTlvNodes(qrisPayload: string): TlvNode[] {
  const nodes: TlvNode[] = [];
  let idx = 0;

  while (idx < qrisPayload.length) {
    if (idx + 4 > qrisPayload.length) {
      throw new Error(`Format TLV QRIS rusak pada indeks ${idx}: header tag/length tidak utuh.`);
    }
    const tag = qrisPayload.slice(idx, idx + 2);
    const lenStr = qrisPayload.slice(idx + 2, idx + 4);
    if (!/^\d{2}$/.test(lenStr)) {
      throw new Error(`Panjang TLV tidak valid untuk tag ${tag}: "${lenStr}".`);
    }
    const length = Number(lenStr);
    const valueStart = idx + 4;
    const valueEnd = valueStart + length;
    if (valueEnd > qrisPayload.length) {
      throw new Error(`Nilai TLV untuk tag ${tag} melebihi panjang string QRIS (${valueEnd} > ${qrisPayload.length}).`);
    }
    const value = qrisPayload.slice(valueStart, valueEnd);
    nodes.push({ tag, length, value });
    idx = valueEnd;
  }

  return nodes;
}

/**
 * Merangkai node TLV kembali menjadi string EMVCo dan menambahkan checksum CRC16-CCITT (Tag 6304).
 */
export function serializeTlvNodesWithCrc(nodesWithoutCrc: TlvNode[]): string {
  const body = nodesWithoutCrc
    .filter((n) => n.tag !== '63')
    .map((n) => `${n.tag}${String(n.value.length).padStart(2, '0')}${n.value}`)
    .join('');
  const withCrcHeader = `${body}6304`;
  const crc = computeCrc16Ccitt(withCrcHeader);
  return `${withCrcHeader}${crc}`;
}

/**
 * Membuat string QRIS Statis EMVCo standar Indonesia yang 100% valid CRC16-nya untuk suatu merchant.
 */
export function buildValidStaticQris(params: {
  nmid: string;
  merchantName: string;
  merchantCity: string;
  postalCode?: string;
}): string {
  const cleanName = params.merchantName.slice(0, 25).toUpperCase();
  const cleanCity = params.merchantCity.slice(0, 15).toUpperCase();
  const postal = (params.postalCode || '52181').slice(0, 10);

  // Sub-TLV untuk Tag 51 (NMID Nasional QRIS Indonesia)
  const gui = '0014ID.CO.QRIS.WWW';
  const nmidTag = `02${String(params.nmid.length).padStart(2, '0')}${params.nmid}`;
  const criteria = '0303UMI';
  const tag51Value = `${gui}${nmidTag}${criteria}`;

  const nodes: TlvNode[] = [
    { tag: '00', length: 2, value: '01' },
    { tag: '01', length: 2, value: '11' }, // 11 = Statis
    { tag: '51', length: tag51Value.length, value: tag51Value },
    { tag: '52', length: 4, value: '7230' }, // MCC Barbershop & Beauty Shops
    { tag: '53', length: 3, value: '360' }, // IDR (Rupiah)
    { tag: '58', length: 2, value: 'ID' },
    { tag: '59', length: cleanName.length, value: cleanName },
    { tag: '60', length: cleanCity.length, value: cleanCity },
    { tag: '61', length: postal.length, value: postal },
  ];

  return serializeTlvNodesWithCrc(nodes);
}

/**
 * Memvalidasi apakah string QRIS statis merupakan format EMVCo Indonesia yang sah dan ber-checksum CRC16 tepat.
 */
export function validateStaticQris(rawQris: string): { valid: boolean; reason?: string } {
  const trimmed = (rawQris || '').trim();
  if (trimmed.length < 24) {
    return { valid: false, reason: 'Payload QRIS terlalu pendek (< 24 karakter).' };
  }
  if (!trimmed.startsWith('000201')) {
    return { valid: false, reason: 'Payload QRIS wajib diawali Payload Format Indicator "000201".' };
  }
  const crcTagPos = trimmed.length - 8;
  if (trimmed.slice(crcTagPos, crcTagPos + 4) !== '6304') {
    return { valid: false, reason: 'Tag CRC "6304" tidak ditemukan pada 8 karakter terakhir.' };
  }

  let nodes: TlvNode[];
  try {
    nodes = parseTlvNodes(trimmed);
  } catch (err: unknown) {
    return { valid: false, reason: err instanceof Error ? err.message : String(err) };
  }

  const hasCountryId = nodes.some((n) => n.tag === '58' && n.value === 'ID');
  if (!hasCountryId) {
    return { valid: false, reason: 'Tag Negara "5802ID" tidak ditemukan dalam payload QRIS.' };
  }

  const hasCurrencyIdr = nodes.some((n) => n.tag === '53' && n.value === '360');
  if (!hasCurrencyIdr) {
    return { valid: false, reason: 'Tag Mata Uang Rupiah "5303360" tidak ditemukan.' };
  }

  const payloadWithoutCrc = trimmed.slice(0, -4);
  const actualCrc = trimmed.slice(-4).toUpperCase();
  const expectedCrc = computeCrc16Ccitt(payloadWithoutCrc);

  if (actualCrc !== expectedCrc) {
    return {
      valid: false,
      reason: `Checksum CRC16 tidak cocok (tertera: ${actualCrc}, seharusnya: ${expectedCrc}).`,
    };
  }

  return { valid: true };
}

/**
 * Mengonversi QRIS Statis milik barbershop menjadi QRIS Dinamis dengan menyuntikkan
 * Tag 54 (Transaction Amount) dan menghitung ulang Checksum CRC16-CCITT (Tag 6304).
 */
export function generateDynamicQris(staticQris: string, exactAmountRupiah: number): string {
  const validation = validateStaticQris(staticQris);
  if (!validation.valid) {
    throw new Error(`QRIS Statis tidak valid: ${validation.reason}`);
  }

  const roundedAmount = Math.round(exactAmountRupiah);
  if (!Number.isFinite(roundedAmount) || roundedAmount < 1) {
    throw new Error(`Nominal QRIS dinamis harus bilangan bulat positif (diterima: ${exactAmountRupiah}).`);
  }

  const amountStr = String(roundedAmount);
  const rawNodes = parseTlvNodes(staticQris.trim()).filter((n) => n.tag !== '63' && n.tag !== '54');

  // Pastikan Tag 01 bernilai '12' (Dinamis)
  const tag01Idx = rawNodes.findIndex((n) => n.tag === '01');
  if (tag01Idx >= 0) {
    rawNodes[tag01Idx] = { tag: '01', length: 2, value: '12' };
  } else {
    rawNodes.splice(1, 0, { tag: '01', length: 2, value: '12' });
  }

  // Sisipkan Tag 54 (Transaction Amount) tepat sebelum Tag 58 (Country Code 'ID')
  const tag54Node: TlvNode = {
    tag: '54',
    length: amountStr.length,
    value: amountStr,
  };

  const tag58Idx = rawNodes.findIndex((n) => n.tag === '58');
  if (tag58Idx >= 0) {
    rawNodes.splice(tag58Idx, 0, tag54Node);
  } else {
    rawNodes.push(tag54Node);
  }

  return serializeTlvNodesWithCrc(rawNodes);
}
