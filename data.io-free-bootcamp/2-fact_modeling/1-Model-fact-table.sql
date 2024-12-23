-- For fact modeling, selecting the right columns and well formatted names matter a lot
-- We have to make sure that the data we provide is easy to work with and gaining insights is easy
-- By using right naming conventions, we make it easy for consumers to differentite metrics and dims
-- We choose the primary key based on query access pattern
DROP TABLE IF EXISTS fact_games;
CREATE Table fact_games (
    dim_game_date date,
    dim_season integer,
    dim_team_id integer,
    dim_player_id integer,
    dim_player_name text,
    dim_start_position text,
    dim_is_playing_at_home boolean,
    dim_did_not_play boolean,
    dim_did_not_dress boolean,
    dim_not_with_team boolean,
    m_minutes REAL,
    m_fgm INTEGER,
    m_fga INTEGER,
    m_fg3a INTEGER,
    m_fg3m INTEGER,
    m_ftm INTEGER,
    m_fta INTEGER,
    m_oreb INTEGER,
    m_dreb INTEGER,
    m_reb INTEGER,
    m_ast INTEGER,
    m_stl INTEGER,
    m_turnovers INTEGER,
    m_pf INTEGER,
    m_pts INTEGER,
    m_plus_minus INTEGER,
    PRIMARY KEY (dim_game_date, dim_player_id, dim_team_id)
);

-- Query to insert deduped records in table
-- We remove data that can easily be recovered with small looksups such as team info
With deduped AS (
    Select g.game_date_est,
           g.season,
           g.visitor_team_id,
           gd.*,
           ROW_NUMBER() over (PARTITION BY gd.game_id, gd.team_id, gd.player_id ORDER BY g.game_date_est) as row_num
    From game_details gd
    Join games g
    ON gd.game_id = g.game_id
)
INSERT INTO fact_games (
    Select game_date_est AS dim_game_date,
           season AS dim_season,
           team_id AS dim_team_id,
           player_id AS dim_player_id,
           player_name AS dim_player_name,
           start_position AS dim_start_position,
           team_id = visitor_team_id                                            AS dim_is_playing_at_home,
           COALESCE(comment like '%DNP%', false)                                as dim_did_not_play,
           COALESCE(comment like '%DND%', false)                                as dim_did_not_dress,
           COALESCE(comment like '%NWT%', false)                                as dim_not_with_team,
           SPLIT_PART(min, ':', 1)::real + SPLIT_PART(min, ':', 2)::real / 60.0 AS m_minutes,
           fgm AS m_fgm,
           fga AS m_fga,
           fg3m AS m_fg3m,
           fg3a AS m_fg3a,
           ftm AS m_ftm,
           fta AS m_fta,
           oreb AS m_oreb,
           dreb AS m_dreb,
           reb AS m_reb,
           ast AS m_ast,
           stl AS m_stl,
           "TO"                                                                 AS m_turnovers,
           pf AS m_pf,
           pts AS m_pts,
           plus_minus AS m_plus_minus
    From deduped
    WHERE row_num = 1 );