-- We have the table containing event data for network history (for 1 month)
select min(event_time), max(event_time)
from events e
limit 100;

-- Example count in a particular day
select count(1)
from events e
where user_id is not null and url not like '%robots%'
and event_time::date = '2023-01-01' 
limit 100;

-- Table that will hold the information
drop table users_activelist;
create table if not exists users_activelist (
	user_id text,
	bit_active bit(32),
	event_date date,  -- reference date for last 32 days of data
	primary key(user_id, event_date)
);

-- Insert into the data incrementally
insert into users_activelist 
with selected_date as (
	select coalesce(max(event_date)::date + INTERVAL '1 day', '2023-01-01'::date) selected_date
	from users_activelist ua 
)
,yesterday as (
	select *
	from users_activelist
	where event_date = (select selected_date from selected_date)::date - INTERVAL '1 day'
),
today as (
	select distinct user_id::text, event_time::date as event_date
	from events e 
	where user_id is not null and url not like '%robots%'  -- Definition of active events
	and event_time::date = (select selected_date from selected_date)  -- Select a new slice to insert for today
)
select coalesce (y.user_id, t.user_id) user_id,
-- We use bit operations to shift the history to right, and set the leftmost bit if user was active today
case 
	when t.user_id is not null
	then set_bit(coalesce(y.bit_active, '0'::bit(32)) >> 1, 0, 1)
	else 
	coalesce(y.bit_active, '0'::bit(32)) >> 1
	END
as bit_active,
coalesce (t.event_date, y.event_date + interval '1 day') as event_date
from yesterday y
full outer join today t
on y.user_id = t.user_id
;

-- Users who were active 3 days in reference from given data
-- but not active on that date itself
select *
from users_activelist
where event_date = '2023-01-15'
and bit_count(bit_active) = 3
and get_bit(bit_active, 0) = 0
;




