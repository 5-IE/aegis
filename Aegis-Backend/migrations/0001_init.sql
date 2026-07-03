CREATE DATABASE `AEGIS`;
USE `AEGIS`;

CREATE TABLE `USER` (
    `id_user` INT AUTO_INCREMENT,
    `username` VARCHAR(50) NOT NULL UNIQUE,
    `password` VARCHAR(64) NOT NULL, -- sha1 hashed
    `email` VARCHAR(100) NOT NULL UNIQUE,
    `role` ENUM('admin', 'learner') NOT NULL DEFAULT 'learner',
    `first_name` VARCHAR(50),
    `last_name` VARCHAR(50),
    `session` ENUM('AM', 'PM') NOT NULL DEFAULT 'AM', -- for learners
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id_user`)
);

CREATE TABLE `ROOM` (
    `id_room` INT AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    PRIMARY KEY (`id_room`)
);

-- iBeacon
CREATE TABLE `DEVICE` (
    `id_device` INT AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `identifier` VARCHAR(100) NOT NULL UNIQUE, -- unique identifier for the device (e.g., major/minor for iBeacon)
    `id_room` INT, -- belongs to a room, can be NULL if not assigned
    PRIMARY KEY (`id_device`),
    FOREIGN KEY (`id_room`) REFERENCES `ROOM`(`id_room`) ON DELETE SET NULL
);

CREATE TABLE `PRESENCE_LOG` (
    `id_log` INT AUTO_INCREMENT,
    `id_user` INT NOT NULL,
    `id_room` INT NOT NULL,
    `timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `position_x` FLOAT DEFAULT NULL,
    `position_y` FLOAT DEFAULT NULL,
    `battery_level` INT DEFAULT NULL,
    PRIMARY KEY (`id_log`),
    FOREIGN KEY (`id_user`) REFERENCES `USER`(`id_user`) ON DELETE CASCADE,
    FOREIGN KEY (`id_room`) REFERENCES `ROOM`(`id_room`) ON DELETE CASCADE
);

CREATE TABLE `ATTENDANCE_HISTORY` (
    `id_user` INT NOT NULL,
    `date` DATE NOT NULL,
    `status` ENUM('early', 'late', 'absent', 'leave') NOT NULL,
    PRIMARY KEY (`id_user`, `date`),
    FOREIGN KEY (`id_user`) REFERENCES `USER`(`id_user`) ON DELETE CASCADE
);
