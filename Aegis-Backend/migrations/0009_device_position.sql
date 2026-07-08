USE `AEGIS`;

-- Beacon position within its room (metres from the room origin). Nullable:
-- an unplaced or unassigned beacon has no position.
ALTER TABLE `DEVICE`
  ADD COLUMN `position_x` FLOAT NULL DEFAULT NULL,
  ADD COLUMN `position_y` FLOAT NULL DEFAULT NULL;
