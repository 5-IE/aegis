USE `AEGIS`;

CREATE TABLE `SESSION_CONFIG` (
  `session` ENUM('AM','PM') NOT NULL PRIMARY KEY,
  `start_time` TIME NOT NULL,
  `late_after` TIME NOT NULL,
  `end_time` TIME NOT NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO `SESSION_CONFIG` (`session`, `start_time`, `late_after`, `end_time`) VALUES
  ('AM', '08:00:00', '08:15:00', '12:00:00'),
  ('PM', '13:00:00', '13:15:00', '17:00:00');
