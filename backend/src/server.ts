import http from 'http';
import express, { type Request, type Response, type NextFunction } from 'express';
import cors from 'cors';
import { Server as SocketIOServer } from 'socket.io';
import pino from 'pino';
import { env } from './config/env.js';
import { tenantRouter } from './routes/tenant.routes.js';
import { createQueueRouter } from './routes/queue.routes.js';
import { mediaRouter } from './routes/media.routes.js';
import { createCashierRouter } from './routes/cashier.routes.js';
import { reportRouter } from './routes/report.routes.js';
import { createPaymentRouter } from './routes/payment.routes.js';

const logger = pino({
  level: env.LOG_LEVEL,
});

export const app = express();
export const server = http.createServer(app);

// Factor VII: Port binding & Real-time WebSocket broadcasting
export const io = new SocketIOServer(server, {
  cors: {
    origin: env.CORS_ORIGIN,
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
  },
});

app.use(cors({ origin: env.CORS_ORIGIN }));
app.use(
  express.json({
    verify: (req: http.IncomingMessage & { rawBody?: string }, _res, buf) => {
      req.rawBody = buf.toString('utf8');
    },
  })
);

// Factor XI: Logs as event streams
app.use((req: Request, res: Response, next: NextFunction) => {
  const start = Date.now();
  res.on('finish', () => {
    logger.info({
      method: req.method,
      url: req.originalUrl,
      status: res.statusCode,
      durationMs: Date.now() - start,
    });
  });
  next();
});

// Health Endpoint
app.get('/health', (_req: Request, res: Response) => {
  res.json({
    status: 'ok',
    environment: env.NODE_ENV,
    uptimeSeconds: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
  });
});

// Domain Routes
app.use('/api/tenants', tenantRouter);
app.use('/api/queue', createQueueRouter(io));
app.use('/api/fuzzy', createQueueRouter(io));
app.use('/api/media', mediaRouter);
app.use('/api/cashier', createCashierRouter(io));
app.use('/api/reports', reportRouter);
app.use('/api/payments', createPaymentRouter(io));

// Start server listening
if (process.env.NODE_ENV !== 'test') {
  server.listen(env.PORT, () => {
    logger.info(`🚀 SmartBarber Twelve-Factor Backend Core aktif pada port ${env.PORT} (${env.NODE_ENV})`);
  });
}
