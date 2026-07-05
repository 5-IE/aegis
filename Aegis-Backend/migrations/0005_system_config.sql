USE `AEGIS`;

CREATE TABLE `SYSTEM_CONFIG` (
  `key` VARCHAR(64) NOT NULL PRIMARY KEY,
  `value` VARCHAR(255) NOT NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO `SYSTEM_CONFIG` (`key`, `value`) VALUES
  ('presence_staleness_minutes', '5'),
  ('timezone', 'Asia/Jakarta');
