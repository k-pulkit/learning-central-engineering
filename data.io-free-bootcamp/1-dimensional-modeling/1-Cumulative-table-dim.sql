-- Source table - Player season contains the information about the players KPIs across different seasons played
Select *
From player_seasons
Limit 100;

-- We create Season stats type representing the player stats that we are interested in
Drop type if exists Season_stats;
Create TYPE Season_stats AS (
    season INTEGER,
    gp real,
    pts real,
    reb real,
    ast real
);

-- Another type created to represented the class of each player
Create TYPE Scoring_class AS ENUM ('star', 'good', 'avg', 'bad');

-- Or Cumulative table will be called players
-- The table like the name suggests will be populated sequentially
-- On each sequemtial run, we will take snapshot of previous run, and modify it to append latest information such that each player's information is limited to one row
-- We make use of data structures such as Arrays of custom types, that allow to compactly pack the data minimizing shuffle and optimizing storing in parquet
Drop table if exists players;
Create Table players (
    player_name text,
    height text,
    college text,
    draft_year text,
    draft_round text,
    draft_number text,
    season_stats Season_stats[],
    scoring_class Scoring_class,
    is_active boolean,
    years_since_last_season INTEGER,
    current_season INTEGER,
    PRIMARY KEY (player_name, current_season)
);
Select min(season), max(season) from player_seasons;

-- We start populating the table using sequential runs
-- Cumulative table inserts
-- Note, we are inserting, so each insert is adding an updated snapshot using today's data altering yesterdays' snap
-- We can select snapshot of a current season using the `current_season` column
-- Run below query 10-15 times to populate data for multiple seasons
TRUNCATE table players;
INSERT INTO players
With yesterday AS (
    Select *
    from players
    WHERE current_season = (Select coalesce(max(current_season), 1995) from players)
),
    today AS (
        Select *
        from player_seasons
        WHERE season = (Select coalesce(max(current_season), 1995)+1 from players)
    )
Select
    coalesce(t.player_name, y.player_name) AS player_name,
    coalesce(t.height, y.height) AS height,
    coalesce(t.college, y.college) AS college,
    coalesce(t.draft_year, y.draft_year) AS draft_year,
    coalesce(t.draft_round, y.draft_round) AS draft_round,
    coalesce(t.draft_number, y.draft_number) AS draft_number,
    CASE WHEN y.season_stats is NULL THEN ARRAY[ROW(t.season, t.gp, t.pts, t.reb, t.ast)::Season_stats]
        WHEN t.season IS NOT NULL THEN y.season_stats || ARRAY[ROW(t.season, t.gp, t.pts, t.reb, t.ast)::Season_stats]
            ELSE y.season_stats END AS season_stats,
    CASE WHEN t.season is not NULL
        THEN
            CASE WHEN t.pts > 20 THEN 'star'
                WHEN t.pts > 15 THEN 'good'
                WHEN t.pts > 10 THEN 'avg'
                ELSE 'bad' END :: Scoring_class
        ELSE y.scoring_class
        END AS scoring_class,
    t.season is not NULL as is_active,
    CASE WHEN t.season is not NULL THEN 0
        ELSE y.years_since_last_season + 1
            END AS years_since_last_season,
    COALESCE(t.season, y.current_season+1) AS current_season
from today t
full outer join yesterday y
On t.player_name = y.player_name;

-- Check how much data is present
select max(current_season)
from players;

-- We can unnest and go back to previous structure of data using un-nest to split arrays across rows, and flattent them into columns
With unnested AS (
    Select player_name, unnest(season_stats) AS season_stats
    from players
    where current_season = 2003
)
Select player_name, (season_stats).*
from unnested;