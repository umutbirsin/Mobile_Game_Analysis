--CASE 2 Q1
--Daily Ad Spend
-- Visualize daily advertising expenses and compare them with the DNU graph.
with nu as
(
select install_date ,
count (distinct user_id) as dnu,
count (distinct case when user_ua_type = 'Organic' then user_id end ) as organic_user,
count (distinct case when user_ua_type = 'Paid' then user_id end ) as paid_user
from `project_game.players` as p
where cast(user_id as int) not in (select*from `project_game.vw_ub_c_d`)
group by 1
), uas as
(
select uas.date,
round ((sum(spend)),2) as total_uaspend
from `project_game.ua_spends` as uas
group by uas.date
order by 1
)
select u.date,
n.dnu,
n.organic_user,
n.paid_user,
u.total_uaspend
from nu as n inner join uas as u on n.install_date = u.date
order by 1

--CASE 2 Q2
--Retention :
-- Calculate cohort-based D1, D3, D7, D14 retention
-- for all dates provided in the dataset and interpret the results as much as possible.

with cohort as
(
select p.install_date,
date_diff(ud.date, p.install_date,DAY) as cohort_age,
count(distinct p.user_id) as cohort_size
from `project_game.players` as p
inner join `project_game.user_daily_activities` as ud on p.user_id = ud .user_id
where cast(p.user_id as int) not in (select * from `project_game.vw_ub_c_d`)
group by 1,2
order by 1
),for_ret as
(
select install_date,
sum  (case when cohort_age = 0 then cohort_size else null end) as day_0,
sum  (case when cohort_age = 1 then cohort_size else null end) as day_1,
sum  (case when cohort_age = 3 then cohort_size else null end) as day_3,
sum  (case when cohort_age = 7 then cohort_size else null end) as day_7,
sum  (case when cohort_age = 14 then cohort_size else null end) as day_14
from cohort
group by 1
)
select install_date,
round( ( (day_1) / (day_0)  ), 2) as Day_1_Ret,
round( ( (day_3) / (day_0)  ), 2)  as Day_3_Ret,
round( ( (day_7) / (day_0)  ), 2) as Day_7_Ret,
round( ((day_14) / (day_0)  ), 2) as Day_14_Ret
from for_ret
;

--CASE 2 Q3
--ARPPU :
-- Calculate ARPPU for all dates provided in the dataset and interpret the trend.
-- Compare ARPPU between the US and PH countries.
----DAILY ARPPU
select
ud.date,
count(distinct case when ud.time_spent_seconds > 0 then  p.user_id end) as DAU,
count(distinct case when purchases > 0 then  p.user_id end) as Spender,
sum (user_spent) as Total_IAP_Revenue,
sum (user_spent) /count(distinct case when ud.user_spent > 0 then p.user_id end) as ARPPU
from `project_game.players` as p
inner join `project_game.user_daily_activities` as ud on p.user_id = ud.user_id
where cast(p.user_id as int) not in (select*from `project_game.vw_ub_c_d`)
group by 1
--- US ve PH comparison
select
ud.date,
country_code_first,
count(distinct case when ud.time_spent_seconds > 0 then  p.user_id end) as DAU,
coalesce ( nullif((count(distinct case when purchases > 0 then  p.user_id end)),0),1  ) as Spender,
sum (user_spent) as Total_IAP_Revenue,
sum (user_spent) /coalesce ( nullif((count(distinct case when purchases > 0 then  p.user_id end)),0),1  )as ARPPU
from `project_game.players` as p
inner join `project_game.user_daily_activities` as ud on p.user_id = ud.user_id and p.install_date = ud.date
where country_code_first in ('US', 'PH') and cast(p.user_id as int) not in (select*from `project_game.vw_ub_c_d`)
group by 1,2

--CASE 2 Q4
--Day n Conversion Rate :
-- What is the D0 conversion rate for players?

with t1 as
(
select
install_date,
date_diff(date, install_date, day) as cohort_age,
count (distinct p.user_id) as cohort_size,
count (distinct case when ud.purchases > 0 then p.user_id end) as spender,
round((count (distinct case when ud.purchases > 0 then p.user_id end) / count (distinct p.user_id) ),2) as CVR
from `project_game.players` as p
inner join `project_game.user_daily_activities`as ud on p.user_id = ud.user_id
where cast(p.user_id as int) not in (select*from `project_game.vw_ub_c_d`) and time_spent_seconds > 0
group by 1,2
)
select
install_date,
cohort_age,
cohort_size,
spender,
CVR as D0CVR
from t1
where cohort_age = 0
;

--CASE 2 Q5
--ROAS :
-- Calculate and interpret the Return on Advertising Spend (ROAS) for D1, D3, D7, and D14.
-- Provide comments on the profitability of the game.

with cohort as
(
select install_date,
date_diff(ud.date,p.install_date, day) as cohort_age,
count(distinct p.user_id) as cohort_size,
round((sum(user_spent) + sum(ad_revenue) ),2)as total_revenue
from `project_game.players` as p
inner join `project_game.user_daily_activities` as ud on p.user_id=ud.user_id
where cast(p.user_id as int) not in (select*from `project_game.vw_ub_c_d`)
group by 1,2
order by 1
),ltv_s as
(
SELECT
    install_date,
    cohort_age,
    SUM(total_revenue) OVER (PARTITION BY install_date ORDER BY cohort_age) AS cumulative_revenue,
    max(cohort_size) OVER (PARTITION BY install_date ORDER BY cohort_age) AS cohort_size
FROM cohort
), ltv_f as
(
select
install_date,
(sum (case when cohort_age =1 then  cumulative_revenue end)) /  max(cohort_size) as d1_ltv,
(sum (case when cohort_age =3 then  cumulative_revenue end)) / max (cohort_size) as d3_ltv,
(sum (case when cohort_age =7 then  cumulative_revenue end)) /  max(cohort_size) as d7_ltv,
(sum (case when cohort_age =14 then  cumulative_revenue end)) / max(cohort_size) as d14_ltv
from ltv_s
group by 1
),cpi as
(
select
p.install_date,
sum(ua.spend) /nullif((pdnu),0) as CPI
from `project_game.ua_spends`as ua
left join (select count(distinct case when user_ua_type='Paid' then user_id end) as pdnu , install_date from `project_game.players` group by 2) as p on p.install_date = ua.date
group by 1,pdnu
)
select
l.install_date,
CPI,
round((d1_ltv),2) as d1_ltv,
d1_ltv / CPI * 100 as D1ROAS,
round((d3_ltv),2) as d3_ltv,
d3_ltv / CPI * 100 as D3ROAS,
round((d7_ltv),2) as d7_ltv,
d7_ltv / CPI * 100 as D7ROAS,
round((d14_ltv),2) as d14_ltv,
d14_ltv / CPI * 100 as D14ROAS,
from ltv_f as l inner join cpi as c on l.install_date = c.install_date
;

--CASE 2 Q6
-- First & Repeat Spenders :
-- Find the number of first-time and repeat spenders
-- within the Daily Active Users (DAU) for all dates provided in the dataset.

with rn as (
select
p.user_id,
ud.date as date,
row_number ()over (partition by p.user_id order by ud.date ) as purchase_number
from `project_game.user_daily_activities` as ud inner join `project_game.players` as p on p.user_id = ud.user_id
where cast(p.user_id as int) not in (select*from `project_game.vw_ub_c_d`) and  purchases >0
group by 1,2
order by 1
), first as
(
select
date,
count (distinct rn.user_id) as first_s
from rn
where purchase_number = 1
group by 1
),repeat as
(
select
date,
count (distinct rn.user_id) as repeat_s
from rn
where purchase_number > 1
group by 1
),dau_t as
(
select
date,
count (distinct p.user_id) as dau
from `project_game.user_daily_activities` as ud inner join `project_game.players` as p on p.user_id = ud.user_id
where cast(p.user_id as int) not in (select*from `project_game.vw_ub_c_d`) and time_spent_seconds > 0
group by 1
)
select
dau_t.date,
sum(dau) as DAU,
sum(first_s) as First_time_spenders,
sum(repeat_s) as Repeat_spenders
from first left join repeat on first.date = repeat.date
left join dau_t on first.date = dau_t.date
group by 1
;
--CASE 3 Q1
-- What could be the most challenging stage (level) for players in the game?
-- Share your own assessment and comments.


----according_to_Fail_attempt----
with t1 as (
select
cast (stage_index as integer) as stage_index,
count (case when result = 'fail' then cast(stage_attempt AS integer) end) as attempt_count,
count (distinct case when result = 'fail' then user_id end ) user_count,
from `project_game.stage_events`
where user_id not in (select * from `project_game.vw_ub_c_d`)
group by 1
order by 1
)
select
distinct stage_index,
round( (attempt_count / user_count),2) as avg_attempt,
user_count
from t1
where user_count > 500
order by 2 desc
limit 5
;
------according_to_suc_rate---
with t1 as
(
select
stage_index,
result,
count(cast (stage_attempt as integer)) as attempt_count,
count(distinct p.user_id) as user_count,
sum(cast (stage_attempt as integer)) / count(distinct p.user_id)  as avg_rate
from `project_game.players` as p
inner join `project_game.stage_events`as se on p.user_id = cast(se.user_id as string)
where result in ('fail','win' ) and type= 'stage_end' and cast(p.user_id as integer) not in (select * from `project_game.vw_ub_c_d`)
group by 1,2--,p.user_id
order by 1,2
)
select
stage_index,
max(case when t1.result ='win' then avg_rate end) / max( case when t1.result ='fail' then avg_rate end) as succes_rate
from t1
where user_count >500
group by 1
order by 1
;

--CASE 3 Q2
-- What stage is most likely for a player who is still in the game on Day 5?

select
date_diff(event_date,install_date,day) as cohort_age,
count(distinct p.user_id) as player_count,
round  (avg (cast (stage_index as int)) ,2)as avg_index
from `project_game.players` as p
inner join `project_game.stage_events` as se on p.user_id = cast(se.user_id as string)
where cast(p.user_id as int) not in (select * from `project_game.vw_ub_c_d`)
group by 1
------

--CASE 3 Q3
-- What stage is a player likely to be on after completing their 21st attempt cumulatively?
with t1 as(
SELECT
count(distinct user_id) as user_count,
cast(stage_index as integer)as stage_index,
count(case when type = 'stage_start' then cast(stage_attempt as int)end) as attempt_count,
FROM `project_game.stage_events`
where user_id not in (select * from `project_game.vw_ub_c_d`)
GROUP BY 2
order by 1,2
)
select t1.stage_index,
attempt_count / user_count as avg_attempt
from t1

--OWN QUESTİON--
-- The Impact of Mobile Device Screen Size on Player Success---------


with t1 as
(
 select device_category ,
stage_index,
 count(case when type = 'stage_end' then cast (stage_attempt as integer) end) as total_attempt,
  count(case when result = 'win' then cast (stage_attempt as integer) end) as win_attempt,
   count(case when result = 'fail' then cast (stage_attempt as integer) end) as fail_attempt
 from `project_game.players` as p
 inner join `project_game.stage_events`as se on p.user_id = cast(se.user_id as string)
 where cast (p.user_id as int) not in (select*from `project_game.vw_ub_c_d`) and result in ('win','fail') and device_category in ('phone','tablet') and cast(stage_index as integer) <= 20
group by 1,2
)
select
cast(stage_index as integer) stage_index,
device_category,
max(win_attempt) / max(fail_attempt) as succes_rate,
from t1
group by 1,2


-----CHEATER VİEW---
--Detected cheaters have been excluded from the analysis by being placed into a separate view.
with t1 as (
select
    us.user_id,
    user_spent,
    max(safe_cast(current_gem as integer )) as max_gem,
    max(safe_cast(current_gold as integer )) as max_gold
from `project_game.players`as p
         inner join `project_game.user_states` as us on p.user_id = cast (us.user_id as string) and us.event_date = p.install_date
         inner join `project_game.user_daily_activities` as ud on p.user_id = ud.user_id and ud.date = p.install_date
group by 1,2
)

select distinct user_id from  t1
where user_spent = 0 and max_gem >1000

