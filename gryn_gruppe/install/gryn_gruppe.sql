-- Optional: the resource creates this table itself on start (CREATE TABLE IF NOT EXISTS).
CREATE TABLE IF NOT EXISTS `gryn_gruppe_players` (
    `identifier`       VARCHAR(60) NOT NULL,
    `xp`               INT NOT NULL DEFAULT 0,
    `level`            INT NOT NULL DEFAULT 1,
    `reputation`       INT NOT NULL DEFAULT 0,
    `jobs_completed`   INT NOT NULL DEFAULT 0,
    `xp_today`         INT NOT NULL DEFAULT 0,
    `money_today`      INT NOT NULL DEFAULT 0,
    `daily_reset`      INT NOT NULL DEFAULT 0,
    `last_daily_claim` INT NOT NULL DEFAULT 0,
    `last_job_end`     INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`identifier`)
);
