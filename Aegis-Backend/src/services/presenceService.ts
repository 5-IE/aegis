import { AppError } from '../lib/errors.js';
import { findRoomById } from '../db/queries/roomQueries.js';
import { insertPresenceLog } from '../db/queries/presenceQueries.js';

export async function recordPresence(
  userId: number,
  input: { room_id: number; position_x?: number | null; position_y?: number | null; battery_level?: number | null },
): Promise<void> {
  const room = await findRoomById(input.room_id);
  if (!room) throw new AppError('invalid_request', 'Unknown room_id');
  await insertPresenceLog({
    userId,
    roomId: input.room_id,
    positionX: input.position_x ?? null,
    positionY: input.position_y ?? null,
    batteryLevel: input.battery_level ?? null,
  });
}
