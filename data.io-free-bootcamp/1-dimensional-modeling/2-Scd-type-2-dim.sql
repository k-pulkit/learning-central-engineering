-- Data source for this dimension will be the cumulative table we created
-- Table name = players

-- Check how much data we have in players source table
Select max(current_season)
from players;

-- Create schema for the SCD Type 2 dimension table
-- Note: This is the only SCD dimension type that is idempotent
Drop table if exists players_scd2;
CREATE table players_scd2 (
    player_name text,
    scoring_class Scoring_class,
    is_active boolean,
    start_season integer,
    end_season integer,
    current_season integer,
    primary key (player_name, start_season)
);

-- First query to convert the players cumulative table into a SCD Type 2 dimension
-- We are interested in 2 columns for change, scoring class and is active
-- We limit data added to <= 2012 to keep some data handly to test the incremental SCD ETL
TRUNCATE players_scd2;
Insert into players_scd2
with with_cols AS (
    Select player_name, scoring_class, is_active, current_season
    from players
    Where current_season <= 2012
),
    with_change AS (
        Select x.player_name, x.current_season,
               x.scoring_class, x.is_active,
               Case
                   WHEN x.scoring_class <> y.scoring_class THEN 1
                   WHEN x.is_active <> y.is_active THEN 1
               ELSE 0 END AS has_changed
        from with_cols x
                 LEFT JOIN with_cols y
                 ON x.player_name = y.player_name
                 AND x.current_season = y.current_season+1
),
    with_streak AS (
        Select *,
           sum(has_changed) OVER (PARTITION BY player_name order by current_season) AS streak
        from with_change
    )
Select player_name, scoring_class, is_active, min(current_season) as start_season, max(current_season) as end_season,
       2012 AS current_season
from with_streak
group by player_name, scoring_class, is_active, streak
order by player_name, streak;

-- Rows which are finalized
Select *
From players_scd2
WHERE end_season < (Select max(end_season) from players_scd2)
LIMIT 4;

-- Rows which may be modified on the incremental SCD Run
Select *
From players_scd2
WHERE end_season = (Select max(current_season) from players_scd2)
LIMIT 4;

-- Incremental SCD ETL
-- We make use of the Postgres 15 MERGE operation to update rows where data has not changes
-- and insert new rows for data which has changed or that is for new players
WITH latest_slice AS (
    Select player_name, scoring_class, is_active, current_season
    from players
    WHERE current_season = (Select max(current_season) from players_scd2) + 1
    )
MERGE INTO players_scd2 AS target
USING latest_slice latest
ON target.player_name = latest.player_name AND target.end_season = (Select max(current_season) from players_scd2)
WHEN MATCHED AND (target.scoring_class = latest.scoring_class AND target.is_active = latest.is_active) THEN
    UPDATE SET end_season = latest.current_season, current_season = latest.current_season
WHEN NOT MATCHED THEN
    INSERT (player_name, scoring_class, is_active, start_season, end_season, current_season)
        VALUES (latest.player_name, latest.scoring_class, latest.is_active, latest.current_season, latest.current_season, latest.current_season);
;