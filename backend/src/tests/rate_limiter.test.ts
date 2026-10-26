import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { createSlidingWindowLimiter } from '../middleware/rateLimiter.js';
import type { Request, Response, NextFunction } from 'express';

describe('🛡️ Pengujian Rate Limiter (Anti-DDoS / Anti-Spam Booking)', () => {
  test('Mengizinkan request dalam batas maksimum (3 req)', () => {
    const limiter = createSlidingWindowLimiter(60_000, 3);
    let nextCalled = 0;
    const req = { headers: {}, socket: { remoteAddress: '192.168.1.10' } } as unknown as Request;
    const res = { status: () => res, json: () => {} } as unknown as Response;
    const next: NextFunction = () => { nextCalled++; };

    limiter(req, res, next);
    limiter(req, res, next);
    limiter(req, res, next);

    assert.strictEqual(nextCalled, 3, 'Tiga request pertama harus diizinkan');
  });

  test('Memblokir request ke-4 dengan status 429 Too Many Requests', () => {
    const limiter = createSlidingWindowLimiter(60_000, 3);
    let statusCode = 200;
    let responseBody: any = null;
    let nextCalled = 0;

    const req = { headers: {}, socket: { remoteAddress: '192.168.1.55' } } as unknown as Request;
    const res = {
      status: (code: number) => {
        statusCode = code;
        return res;
      },
      json: (body: any) => {
        responseBody = body;
      },
    } as unknown as Response;
    const next: NextFunction = () => { nextCalled++; };

    // 3 request awal diizinkan
    limiter(req, res, next);
    limiter(req, res, next);
    limiter(req, res, next);

    // Request ke-4 harus diblokir
    limiter(req, res, next);

    assert.strictEqual(nextCalled, 3, 'Next tidak boleh dipanggil pada request ke-4');
    assert.strictEqual(statusCode, 429, 'Status code harus 429 Too Many Requests');
    assert.ok(responseBody?.error, 'Response body harus memiliki pesan error batas tercapai');
  });
});
