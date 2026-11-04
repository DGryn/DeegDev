-- recycling_warehouse: one table for XP, lifetime stats and today's goals.
-- The resource creates this automatically when Config.AutoCreateTable = true,
-- so you only need to run this yourself if you turned that off.

CREATE TABLE IF NOT EXISTS `recycling_warehouse_players` (
    `identifier` VARCHAR(64) NOT NULL,          -- ESX character identifier
    `xp` INT UNSIGNED NOT NULL DEFAULT 0,
    `boxes_delivered` INT UNSIGNED NOT NULL DEFAULT 0,
    `skill_hits` INT UNSIGNED NOT NULL DEFAULT 0,
    `trades` INT UNSIGNED NOT NULL DEFAULT 0,
    `rare_finds` INT UNSIGNED NOT NULL DEFAULT 0,
    `goals_completed` INT UNSIGNED NOT NULL DEFAULT 0,
    `shifts` INT UNSIGNED NOT NULL DEFAULT 0,
    `goals_day` VARCHAR(10) NULL DEFAULT NULL,  -- the day today's goals belong to (YYYY-MM-DD)
    `goals` LONGTEXT NULL DEFAULT NULL,         -- today's goals and progress (JSON)
    PRIMARY KEY (`identifier`)
);
