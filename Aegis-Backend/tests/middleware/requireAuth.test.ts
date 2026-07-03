import { describe, it, expect, vi, beforeAll } from 'vitest';
import type { Request, Response, NextFunction } from 'express';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

const load = async () => {
  const mw = await import('../../src/middleware/requireAuth.js');
  const tokens = await import('../../src/services/tokenService.js');
  return { mw, tokens };
};

function mockRes() {
  return {} as Response;
}

describe('requireAuth', () => {
  it('attaches user for a valid Bearer token', async () => {
    const { mw, tokens } = await load();
    const token = tokens.signAccessToken({ sub: 42, role: 'learner', session: 'AM' });
    const req = { headers: { authorization: `Bearer ${token}` } } as unknown as Request;
    const next = vi.fn() as unknown as NextFunction;
    mw.requireAuth(req, mockRes(), next);
    expect((req as any).user).toEqual({ id: 42, role: 'learner', session: 'AM' });
    expect(next).toHaveBeenCalledWith();
  });

  it('calls next with unauthorized error when header missing', async () => {
    const { mw } = await load();
    const req = { headers: {} } as unknown as Request;
    const next = vi.fn() as unknown as NextFunction;
    mw.requireAuth(req, mockRes(), next);
    const err = (next as any).mock.calls[0][0];
    expect(err.code).toBe('unauthorized');
  });

  it('calls next with unauthorized error when token invalid', async () => {
    const { mw } = await load();
    const req = { headers: { authorization: 'Bearer bogus' } } as unknown as Request;
    const next = vi.fn() as unknown as NextFunction;
    mw.requireAuth(req, mockRes(), next);
    const err = (next as any).mock.calls[0][0];
    expect(err.code).toBe('unauthorized');
  });
});
