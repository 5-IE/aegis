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

const load = () => import('../../src/middleware/requireRole.js');

describe('requireRole', () => {
  it('passes when role matches', async () => {
    const { requireRole } = await load();
    const req = { user: { id: 1, role: 'admin' as const } } as unknown as Request;
    const next = vi.fn() as unknown as NextFunction;
    requireRole('admin')(req, {} as Response, next);
    expect(next).toHaveBeenCalledWith();
  });

  it('rejects with forbidden when role mismatches', async () => {
    const { requireRole } = await load();
    const req = { user: { id: 1, role: 'learner' as const } } as unknown as Request;
    const next = vi.fn() as unknown as NextFunction;
    requireRole('admin')(req, {} as Response, next);
    const err = (next as any).mock.calls[0][0];
    expect(err.code).toBe('forbidden');
  });

  it('rejects with unauthorized when no user attached', async () => {
    const { requireRole } = await load();
    const req = {} as Request;
    const next = vi.fn() as unknown as NextFunction;
    requireRole('admin')(req, {} as Response, next);
    const err = (next as any).mock.calls[0][0];
    expect(err.code).toBe('unauthorized');
  });
});
