import { Router, type Request, type Response } from 'express';
import { env } from '../config/env.js';

export const mediaRouter = Router();

mediaRouter.post('/presign-upload', (req: Request, res: Response) => {
  const { filename, contentType } = req.body as { filename?: string; contentType?: string };
  if (!filename) {
    res.status(400).json({ error: 'Nama berkas (filename) wajib diisi.' });
    return;
  }

  const fileKey = `proofs/${Date.now()}-${filename.replace(/[^a-zA-Z0-9.-]/g, '_')}`;
  const uploadUrl = `${env.S3_ENDPOINT}/${env.S3_BUCKET}/${fileKey}`;

  res.json({
    uploadUrl,
    fileKey,
    publicUrl: uploadUrl,
    contentType: contentType || 'image/jpeg',
  });
});
