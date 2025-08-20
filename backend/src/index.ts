import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import { PrismaClient } from '@prisma/client';
import { z } from 'zod';
import fetch from 'cross-fetch';
import cookieParser from 'cookie-parser';
import jwt from 'jsonwebtoken';
import nacl from 'tweetnacl';
import bs58 from 'bs58';

const app = express();
// Strict CORS for cookie-based auth
app.use((req: Request, res: Response, next: NextFunction) => {
  const origin = req.headers.origin as string | undefined;
  const allowList = new Set(['http://localhost:3000', 'http://127.0.0.1:3000']);
  if (origin && allowList.has(origin)) {
    res.header('Access-Control-Allow-Origin', origin);
    res.header('Vary', 'Origin');
    res.header('Access-Control-Allow-Credentials', 'true');
    res.header('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  }
  if (req.method === 'OPTIONS') {
    return res.sendStatus(204);
  }
  next();
});
app.use(express.json());
app.use(cookieParser());

const prisma = new PrismaClient();
const PORT = process.env.PORT ? Number(process.env.PORT) : 8080;
const SOLANA_RPC_URL = process.env.SOLANA_RPC_URL || 'https://api.devnet.solana.com';
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change';
const ADMIN_WALLETS = new Set(
  (process.env.ADMIN_WALLETS || process.env.ADMIN_WALLET || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
);

// Simple in-memory SSE subscribers per election
const subscribers: Map<number, Set<Response>> = new Map();

async function computeStats(electionId: number) {
  const grouped = await prisma.vote.groupBy({
    by: ['candidateId', 'candidateName'],
    where: { electionId },
    _count: { _all: true }
  });
  return grouped.map((g: any) => ({ candidateId: g.candidateId, candidateName: g.candidateName, votes: g._count._all }));
}

async function pushStatsToSubscribers(electionId: number) {
  const set = subscribers.get(electionId);
  if (!set || set.size === 0) return;
  const stats = await computeStats(electionId);
  const payload = `data: ${JSON.stringify({ type: 'stats', stats })}\n\n`;
  for (const res of Array.from(set) as any[]) {
    try {
      res.write(payload);
    } catch {
      // Drop any broken connection
      set.delete(res);
    }
  }
}

app.get('/health', (_req: Request, res: Response) => res.json({ ok: true }));

// Public elections API
app.get('/api/elections/active', async (_req: Request, res: Response) => {
  const active = await prisma.election.findFirst({ where: { status: 'ACTIVE' as any }, include: { candidates: true } });
  if (!active) return res.json({});
  res.json(active);
});

// Public: list active elections (lightweight)
app.get('/api/elections', async (_req: Request, res: Response) => {
  const els = await prisma.election.findMany({
    where: { status: 'ACTIVE' as any },
    orderBy: { startDate: 'desc' },
    select: { id: true, title: true, description: true, level: true, status: true, startDate: true, endDate: true }
  });
  res.json(els);
});

// Public: election details with candidates
app.get('/api/elections/:id', async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (isNaN(id)) return res.status(400).json({ error: 'invalid id' });
  const el = await prisma.election.findUnique({ where: { id }, include: { candidates: true } });
  if (!el) return res.status(404).json({ error: 'not found' });
  res.json(el);
});

// Voter endpoints: basic CRUD and verification
app.get('/api/voters', async (_req: Request, res: Response) => {
  const voters = await prisma.voter.findMany({ orderBy: { createdAt: 'desc' } });
  res.json(voters);
});

app.post('/api/voters', requireAdmin as any, async (req: Request, res: Response) => {
  try {
    const input = z.object({
      name: z.string().min(1),
      matric: z.string().min(3),
      email: z.string().email().optional(),
      department: z.string().optional(),
      eligible: z.boolean().optional()
    }).parse(req.body);
    const created = await prisma.voter.create({ data: {
      name: input.name,
      matric: input.matric,
      email: input.email,
      department: input.department,
      eligible: input.eligible ?? true
    }});
    res.status(201).json(created);
  } catch (e: any) {
    if (e?.code === 'P2002') return res.status(409).json({ error: 'matric already exists' });
    res.status(400).json({ error: 'invalid payload' });
  }
});

app.patch('/api/voters/:id', requireAdmin as any, async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (isNaN(id)) return res.status(400).json({ error: 'invalid id' });
  try {
    const data = z.object({
      name: z.string().min(1).optional(),
      email: z.string().email().optional(),
      department: z.string().optional(),
      eligible: z.boolean().optional(),
      matric: z.string().min(3).optional()
    }).parse(req.body ?? {});
    const updated = await prisma.voter.update({ where: { id }, data: {
      name: data.name,
      email: data.email,
      department: data.department,
      eligible: data.eligible,
      matric: data.matric
    }});
    res.json(updated);
  } catch (e: any) {
    res.status(400).json({ error: 'update failed' });
  }
});

app.delete('/api/voters/:id', requireAdmin as any, async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (isNaN(id)) return res.status(400).json({ error: 'invalid id' });
  try {
    await prisma.voter.delete({ where: { id } });
    res.json({ ok: true });
  } catch {
    res.status(404).json({ error: 'not found' });
  }
});

app.get('/api/voters/verify/:matric', async (req: Request, res: Response) => {
  const matric = String(req.params.matric || '').trim();
  if (!matric) return res.status(400).json({ ok: false });
  const voter = await prisma.voter.findUnique({ where: { matric } });
  if (!voter || voter.eligible === false) return res.json({ ok: false });
  res.json({ ok: true, voter });
});

// Attach a wallet to voter by matric (called after wallet connect)
app.post('/api/voters/wallet', async (req: Request, res: Response) => {
  try {
    const body = z.object({ matric: z.string().min(3), walletAddress: z.string().min(32) }).parse(req.body);
    const voter = await prisma.voter.findUnique({ where: { matric: body.matric } });
    if (!voter) return res.status(404).json({ ok: false, error: 'matric not found' });
    if (voter.walletAddress && voter.walletAddress !== body.walletAddress) {
      return res.status(409).json({ ok: false, error: 'matric already linked to a wallet' });
    }
    const byWallet = await prisma.voter.findUnique({ where: { walletAddress: body.walletAddress } }).catch(()=>null);
    if (byWallet && byWallet.matric !== body.matric) {
      return res.status(409).json({ ok: false, error: 'wallet already linked to another matric' });
    }
    const updated = await prisma.voter.update({
      where: { matric: body.matric },
      data: { walletAddress: body.walletAddress, walletVerified: true, walletVerifiedAt: new Date() }
    });
    res.json({ ok: true, voter: updated });
  } catch (e: any) {
    if (e?.code === 'P2002') return res.status(409).json({ ok: false, error: 'wallet already linked' });
    res.status(400).json({ ok: false });
  }
});

// Auth: nonce issuance
const NonceStore = new Map<string, number>(); // address -> nonce
app.post('/auth/nonce', async (req: Request, res: Response) => {
  const address = String(req.body?.address || '').trim();
  if (!address) return res.status(400).json({ error: 'address required' });
  const nonce = Math.floor(Math.random() * 1e9);
  NonceStore.set(address, nonce);
  res.json({ nonce, statement: 'Sign in to Mac Votes (Devnet)', domain: req.hostname });
});

// Verify signed message and issue JWT
app.post('/auth/verify', async (req: Request, res: Response) => {
  try {
    const { address, signature, nonce } = req.body || {};
    if (!address || signature == null || typeof nonce !== 'number') {
      return res.status(400).json({ error: 'invalid payload' });
    }
    const expected = NonceStore.get(address);
    if (expected !== nonce) return res.status(400).json({ error: 'invalid nonce' });

    const msg = new TextEncoder().encode(`Sign in to Mac Votes: ${nonce}`);
    let sigBytes: Uint8Array;
    if (typeof signature === 'string') sigBytes = bs58.decode(signature);
    else if (Array.isArray(signature)) sigBytes = Uint8Array.from(signature as number[]);
    else return res.status(400).json({ error: 'invalid signature format' });
    const pubkeyBytes = bs58.decode(address);
    const ok = nacl.sign.detached.verify(msg, sigBytes, pubkeyBytes);
    if (!ok) return res.status(401).json({ error: 'bad signature' });

    // Upsert user, default VIEWER
    let user = await prisma.user.upsert({
      where: { walletAddress: address },
      update: {},
      create: { walletAddress: address }
    });

    // Promote to ADMIN if configured or if no admin exists yet (bootstrap)
    try {
      const adminCount = await prisma.user.count({ where: { role: 'ADMIN' as any } });
      if ((ADMIN_WALLETS.has(address) || adminCount === 0) && user.role !== 'ADMIN') {
        user = await prisma.user.update({ where: { id: user.id }, data: { role: 'ADMIN' as any } });
      }
    } catch {}

    // Link voter record if exists by matric later on; ensure voter with same wallet is marked verified
    try {
      await prisma.voter.updateMany({
        where: { walletAddress: address },
        data: { walletVerified: true, walletVerifiedAt: new Date() }
      });
    } catch {}

    const token = jwt.sign({ sub: user.id, role: user.role, address }, JWT_SECRET, { expiresIn: '1h' });
    res.cookie('token', token, { httpOnly: true, sameSite: 'lax', secure: false, maxAge: 3600_000 });
    res.json({ ok: true, role: user.role });
  } catch (e:any) {
    console.error('auth verify error', e);
    res.status(500).json({ error: 'verify failed' });
  }
});

app.post('/auth/logout', (_req: Request, res: Response) => {
  res.clearCookie('token');
  res.json({ ok: true });
});

function requireAdmin(req: Request, res: Response, next: NextFunction) {
  const token = req.cookies?.token;
  if (!token) return res.status(401).json({ error: 'unauthorized' });
  try {
    const payload = jwt.verify(token, JWT_SECRET) as any;
    if (payload.role !== 'ADMIN') return res.status(403).json({ error: 'forbidden' });
    (req as any).user = payload;
    next();
  } catch {
    res.status(401).json({ error: 'unauthorized' });
  }
}

const VoteInput = z.object({
  signature: z.string().min(10),
  electionId: z.number().int(),
  candidateId: z.number().int(),
  candidateName: z.string().min(1),
  matric: z.string().min(3),
  walletAddress: z.string().min(32),
  network: z.string().default('devnet')
});

async function getSignatureStatus(signature: string) {
  const body = {
    jsonrpc: '2.0',
    id: 1,
    method: 'getSignatureStatuses',
    params: [[signature], { searchTransactionHistory: true }]
  };
  const resp = await fetch(SOLANA_RPC_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  const json = (await resp.json()) as any;
  return json?.result?.value?.[0];
}

app.post('/api/votes', async (req: Request, res: Response) => {
  try {
    const input = VoteInput.parse(req.body);

    // Verify signature confirms on-chain
    const status = await getSignatureStatus(input.signature);
    if (!status || status.err) {
      return res.status(400).json({ error: 'Signature not found or failed', status });
    }

    const saved = await prisma.vote.create({ data: input });
    // Update voter activity on successful vote
    try {
      const voter = await prisma.voter.findFirst({ where: { matric: input.matric } });
      if (voter) {
        await prisma.voter.update({ where: { id: voter.id }, data: { lastVoteSignature: input.signature, lastVoteAt: new Date(), walletAddress: input.walletAddress } });
      }
    } catch {}
    // Notify SSE subscribers for this election
    pushStatsToSubscribers(input.electionId).catch(() => {});
    res.json(saved);
  } catch (err: any) {
    if (err?.code === 'P2002') {
      return res.status(200).json({ ok: true, duplicate: true });
    }
    if (err instanceof z.ZodError) {
      return res.status(400).json({ error: 'Invalid input', details: err.flatten() });
    }
    console.error(err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/api/votes', async (req: Request, res: Response) => {
  const electionId = Number((req.query as any).electionId);
  const votes = await prisma.vote.findMany({ where: isNaN(electionId) ? {} : { electionId } });
  res.json(votes);
});

app.get('/api/votes/:signature', async (req: Request, res: Response) => {
  const vote = await prisma.vote.findUnique({ where: { signature: req.params.signature } });
  if (!vote) return res.status(404).json({ error: 'Not found' });
  res.json(vote);
});

// Public: check if a matric has voted in an election
app.get('/api/votes/hasVoted', async (req: Request, res: Response) => {
  const electionId = Number(String((req.query as any).electionId || ''));
  const matric = String((req.query as any).matric || '').trim();
  if (isNaN(electionId) || !matric) return res.json({ ok: false, hasVoted: false });
  const existing = await prisma.vote.findFirst({ where: { electionId, matric } });
  res.json({ ok: true, hasVoted: !!existing });
});

// Aggregate stats per candidate for an election
app.get('/api/stats/:electionId', async (req: Request, res: Response) => {
  const electionId = Number(req.params.electionId);
  if (isNaN(electionId)) return res.status(400).json({ error: 'Invalid electionId' });
  const grouped: any[] = await prisma.vote.groupBy({
    by: ['candidateId', 'candidateName'],
    where: { electionId },
    _count: { _all: true }
  } as any);
  res.json(grouped.map((g: any) => ({ candidateId: g.candidateId, candidateName: g.candidateName, votes: g._count._all })));
});

// Real-time updates via Server-Sent Events
app.get('/api/stream/:electionId', async (req: Request, res: Response) => {
  const electionId = Number(req.params.electionId);
  if (isNaN(electionId)) return res.status(400).end();
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders?.();

  // Add subscriber
  const set = subscribers.get(electionId) ?? new Set<Response>();
  set.add(res);
  subscribers.set(electionId, set);

  // Send initial stats
  try {
    const stats = await computeStats(electionId);
    res.write(`data: ${JSON.stringify({ type: 'stats', stats })}\n\n`);
  } catch {}

  const keepAlive = setInterval(() => {
    try { res.write(':\n\n'); } catch { /* ignore */ }
  }, 25000);

  req.on('close', () => {
    clearInterval(keepAlive);
    const s = subscribers.get(electionId);
    s?.delete(res);
  });
});

// Admin: basic Elections CRUD (minimal)
const ElectionInput = z.object({
  title: z.string().min(1),
  description: z.string().min(1),
  level: z.enum(['UNIVERSITY', 'FACULTY', 'DEPARTMENT']),
  startDate: z.string(),
  endDate: z.string(),
  candidates: z.array(z.object({
    name: z.string(), department: z.string(), level: z.string(), avatar: z.string(), color: z.string()
  })).min(2)
});

app.post('/admin/elections', requireAdmin, async (req: Request, res: Response) => {
  try {
    const input = ElectionInput.parse(req.body);
    const created = await prisma.election.create({
      data: {
        title: input.title,
        description: input.description,
        level: input.level as any,
        status: 'ACTIVE' as any,
        startDate: new Date(input.startDate),
        endDate: new Date(input.endDate),
        candidates: { create: input.candidates }
      },
      include: { candidates: true }
    });
    res.json(created);
  } catch (e: any) {
    res.status(400).json({ error: 'invalid payload' });
  }
});

app.get('/admin/elections', requireAdmin, async (_req: Request, res: Response) => {
  const all = await prisma.election.findMany({ include: { candidates: true } });
  res.json(all);
});

app.patch('/admin/elections/:id/status', requireAdmin, async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  const status = String(req.body?.status || 'ACTIVE').toUpperCase();
  const updated = await prisma.election.update({ where: { id }, data: { status: status as any } });
  res.json(updated);
});

app.listen(PORT, () => {
  console.log(`API listening on :${PORT}`);
});


