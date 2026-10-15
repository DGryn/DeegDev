-- dg_cocaine plant persistence. Timestamps are unix seconds (os.time() on the server).
CREATE TABLE IF NOT EXISTS `dg_cocaine_plants` (
    `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `owner`      VARCHAR(64)  NOT NULL,           -- ESX identifier of the player who planted it
    `x`          FLOAT        NOT NULL,
    `y`          FLOAT        NOT NULL,
    `z`          FLOAT        NOT NULL,
    `planted_at` INT UNSIGNED NOT NULL,
    `watered_at` INT UNSIGNED NULL DEFAULT NULL,  -- NULL = not watered yet (not growing)
    `fertilised` TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `owner` (`owner`)
);
