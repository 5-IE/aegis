import { AppError } from '../lib/errors.js';
import { hashPassword } from './passwordService.js';
import { revokeAllRefreshTokensForUser } from '../db/queries/refreshTokenQueries.js';
import {
  UserRow,
  findUserByIdAnyState,
  findUserByUsernameAnyState,
  findUserByEmailActive,
  insertUser,
  listUsers,
  updateUserFields,
  updateUserPassword,
  softDeleteUser,
  reactivateUser,
  countActiveAdmins,
} from '../db/queries/userQueries.js';

export interface PublicUser {
  id: number;
  username: string;
  email: string;
  role: 'admin' | 'learner';
  session: 'AM' | 'PM';
  first_name: string | null;
  last_name: string | null;
  is_active: boolean;
  created_at: string;
}

export function toPublicUser(row: UserRow): PublicUser {
  return {
    id: row.id_user,
    username: row.username,
    email: row.email,
    role: row.role,
    session: row.session,
    first_name: row.first_name,
    last_name: row.last_name,
    is_active: row.is_active,
    created_at: row.created_at.toISOString(),
  };
}

export async function listUsersService(
  filter: { role?: 'admin' | 'learner'; session?: 'AM' | 'PM'; name?: string; includeInactive?: boolean },
  page: number,
  perPage: number,
): Promise<{ list: PublicUser[]; total: number; page: number; per_page: number }> {
  const { list, total } = await listUsers(filter, page, perPage);
  return {
    list: list.map(toPublicUser),
    total,
    page,
    per_page: perPage,
  };
}

export async function getUserService(id: number): Promise<PublicUser> {
  const row = await findUserByIdAnyState(id);
  if (!row) throw new AppError('not_found', 'User not found');
  return toPublicUser(row);
}

export async function createUserService(input: {
  username: string;
  password: string;
  email: string;
  role: 'admin' | 'learner';
  session?: 'AM' | 'PM';
  first_name?: string | null;
  last_name?: string | null;
}): Promise<PublicUser> {
  if (input.role === 'learner' && input.session === undefined) {
    throw new AppError('invalid_request', 'session is required when role is learner');
  }

  const existingByUsername = await findUserByUsernameAnyState(input.username);
  if (existingByUsername) {
    throw new AppError('conflict', 'Username already exists');
  }
  const existingByEmail = await findUserByEmailActive(input.email);
  if (existingByEmail) {
    throw new AppError('conflict', 'Email already exists');
  }

  const passwordHash = await hashPassword(input.password);
  const id = await insertUser({
    username: input.username,
    passwordHash,
    email: input.email,
    role: input.role,
    firstName: input.first_name ?? undefined,
    lastName: input.last_name ?? undefined,
    session: input.role === 'learner' ? input.session : undefined,
  });
  const row = await findUserByIdAnyState(id);
  if (!row) throw new AppError('internal_error', 'User created but could not be read back');
  return toPublicUser(row);
}

export async function updateUserService(
  id: number,
  patch: {
    email?: string;
    role?: 'admin' | 'learner';
    session?: 'AM' | 'PM';
    first_name?: string | null;
    last_name?: string | null;
  },
): Promise<PublicUser> {
  if (Object.keys(patch).length === 0) {
    throw new AppError('invalid_request', 'Empty patch');
  }

  const existing = await findUserByIdAnyState(id);
  if (!existing) throw new AppError('not_found', 'User not found');

  // Uniqueness: if email is changing, ensure it is not held by another active user.
  if (patch.email !== undefined && patch.email !== existing.email) {
    const collide = await findUserByEmailActive(patch.email);
    if (collide && collide.id_user !== id) {
      throw new AppError('conflict', 'Email already exists');
    }
  }

  // If final role would be 'learner', ensure a session is defined (either in patch or already present).
  const finalRole = patch.role ?? existing.role;
  if (finalRole === 'learner') {
    const finalSession = patch.session ?? existing.session;
    if (finalSession === undefined) {
      throw new AppError('invalid_request', 'session is required when role is learner');
    }
  }

  await updateUserFields(id, patch);
  const fresh = await findUserByIdAnyState(id);
  if (!fresh) throw new AppError('internal_error', 'User updated but could not be read back');
  return toPublicUser(fresh);
}

export async function resetPasswordService(id: number, newPassword: string): Promise<void> {
  const existing = await findUserByIdAnyState(id);
  if (!existing) throw new AppError('not_found', 'User not found');
  const hash = await hashPassword(newPassword);
  await updateUserPassword(id, hash);
  await revokeAllRefreshTokensForUser(id);
}

export async function deleteUserService(targetId: number, requesterId: number): Promise<void> {
  if (targetId === requesterId) {
    throw new AppError('invalid_request', 'Cannot delete yourself');
  }
  const target = await findUserByIdAnyState(targetId);
  if (!target) throw new AppError('not_found', 'User not found');
  if (target.role === 'admin' && target.is_active) {
    const activeAdmins = await countActiveAdmins();
    if (activeAdmins <= 1) {
      throw new AppError('invalid_request', 'Cannot delete the last active admin');
    }
  }
  await softDeleteUser(targetId);
  await revokeAllRefreshTokensForUser(targetId);
}

export async function reactivateUserService(id: number): Promise<void> {
  const existing = await findUserByIdAnyState(id);
  if (!existing) throw new AppError('not_found', 'User not found');
  await reactivateUser(id);
}
