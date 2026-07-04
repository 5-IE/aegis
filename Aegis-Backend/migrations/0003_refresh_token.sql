USE `AEGIS`;
CREATE TABLE `REFRESH_TOKEN` (
    `id_token` INT AUTO_INCREMENT,
    `id_user` INT NOT NULL,
    `token_hash` CHAR(64) NOT NULL UNIQUE,
    `expires_at` TIMESTAMP NOT NULL,
    `revoked_at` TIMESTAMP NULL,
    `replaced_by_id` INT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id_token`),
    FOREIGN KEY (`id_user`) REFERENCES `USER`(`id_user`) ON DELETE CASCADE,
    FOREIGN KEY (`replaced_by_id`) REFERENCES `REFRESH_TOKEN`(`id_token`) ON DELETE SET NULL,
    INDEX `idx_user` (`id_user`),
    INDEX `idx_expires` (`expires_at`)
);
