// backend/src/middleware/rateLimiter.ts
// 12-Factor Stateless In-Memory Sliding Window Rate Limiter
import type { Request, Response, NextFunction } from 'express';

interface RateLimitRecord {
  timestamps: number[];
}

export function createSlidingWindowLimiter(windowMs: number = 60_000, maxRequests: number = 5) {
  const store = new Map<string, RateLimitRecord>();

  return function rateLimiter(req: Request, res: Response, next: NextFunction): void {
    const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress || '127.0.0.1';
    const key = Array.isArray(ip) ? ip[0] : (typeof ip === 'string' ? ip.split(',')[0].trim() : '127.0.0.1');
    const now = Date.now();
    const windowStart = now - windowMs;

    const record = store.get(key) || { timestamps: [] };
    const recentTimestamps = record.timestamps.filter((t) => t > windowStart);

    if (recentTimestamps.length >= maxRequests) {
      res.status(429).json({
        error: 'Terlalu banyak permintaan reservasi antrean.',
        message: 'Batas kecepatan tercapai. Silakan coba kembali dalam beberapa detik.',
        retryAfterSec: Math.ceil((recentTimestamps[0] + windowMs - now) / 1000),
      });
      return;
    }

    recentTimestamps.push(now);
    store.set(key, { timestamps: recentTimestamps });

    // Auto-clean stale keys
    if (store.size > 2000) {
      for (const [k, v] of store.entries()) {
        const valid = v.timestamps.filter((t) => t > windowStart);
        if (valid.length === 0) store.delete(k);
      }
    }

    next();
  };
}
