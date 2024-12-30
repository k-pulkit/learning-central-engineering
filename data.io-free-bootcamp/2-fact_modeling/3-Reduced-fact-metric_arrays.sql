

-- In this activity, we want to make the table
-- that accumulates metric values over time creating reduced fact tables for large data analysis
-- and allow for easy anaysis

-- create the schema to hold metric data
drop table array_metrics;
create table if not exists array_metrics (
user_id text,
month_start date,
metric_name text,
metric_array real[],
date_last_updated date,
primary key (user_id, month_start, metric_name)
);

-- clear data
truncate array_metrics;

-- create procedure to update data for some argument day
create or replace procedure update_site_hits(i_date date)
language plpgsql
as $$
begin
	with data_to_merge as (
	    select 
	        user_id::text as user_id, 
	        date_trunc('month', event_time::date)::date as month_start,
	        'site_hits' as metric_name,
	        event_time::date as date_last_updated,
	        count(1) as metric_value
	    from events 
	    where user_id is not null
	      and event_time::date = i_date
	    group by 1, 2, 3, 4
	),
	existing_data as (
		select *
		from array_metrics
		where month_start = date_trunc('month', i_date)
	)
	insert into array_metrics (user_id, month_start, metric_name, metric_array, date_last_updated)
	select 
	    coalesce(d.user_id, e.user_id), 
	    coalesce(d.month_start, e.month_start), 
	    coalesce(d.metric_name, e.metric_name), 
		case 
			when e.metric_array is not null then
				e.metric_array || array[coalesce(d.metric_value, 0)]
			when e.metric_array is null then
				array_fill(0, array[d.date_last_updated - d.month_start]) || array[coalesce(d.metric_value, 0)]
		end,
	    coalesce(d.date_last_updated, e.date_last_updated + interval '1 day')
	from data_to_merge d
	full outer join existing_data e
	on (d.user_id = e.user_id and d.month_start = e.month_start and d.metric_name = e.metric_name)
	on conflict (user_id, month_start, metric_name)
	do 
		update set metric_array = excluded.metric_array,
			date_last_updated = excluded.date_last_updated;	
commit;
end;$$;

-- Run a loop for all days
DO $$
DECLARE
    i_date DATE := '2023-01-01';
    end_date DATE := '2023-01-30';
begin
	while i_date <= end_date LOOP
		call update_site_hits(i_date);
		RAISE NOTICE 'Processing date: %', i_date;
		i_date := i_date + interval '1 day';
	end loop;
end; $$;

-- Check result
select *
from array_metrics
where user_id = '15342341988434300000'
;

-- ensure all arrays are of same size
-- Check result
select distinct cardinality (metric_array)
from array_metrics
;





