import { Router } from 'express';
import { requireAuth } from '../middleware/requireAuth.js';
import { listAssignedDevices } from '../db/queries/deviceQueries.js';

export const beaconsRouter = Router();

beaconsRouter.get('/', requireAuth, async (_req, res, next) => {
  try {
    const rows = await listAssignedDevices();
    res.json({
      list: rows.map((r) => ({
        beacon_identifier: r.identifier,
        room_id: r.id_room,
        position_x: r.position_x,
        position_y: r.position_y,
        room_name: r.room_name,
      })),
    });
  } catch (err) {
    next(err);
  }
});
