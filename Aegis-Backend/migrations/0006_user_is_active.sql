USE `AEGIS`;

ALTER TABLE `USER`
  ADD COLUMN `is_active` BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX `idx_user_active` ON `USER` (`is_active`);
