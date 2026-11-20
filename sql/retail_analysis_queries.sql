/* Retail Orders Analysis - SQL Server
   Table: retail_db.dbo.df_orders (9,487 rows, 2022-2023)
   Question: where does the store make and lose money, and are discounts worth it? */


USE retail_db;
GO
--1. overall numbers

select 
count(*) as order_lines,
count(distinct product_id) as products,
round(sum(revenue),0) as revenue,
round(sum(total_profit),0) as profit,
round(sum(total_profit)*100.0/sum(revenue),1)as margin_pct
from df_orders;
-- Result: 9,487 lines, $11.08M revenue, $1.04M profit, 9.4% margin.


--2. how many order lines lose money?
select 
case when profit < 0 then 'loss'
	when profit = 0 then 'neutral'
	else 'profit' end as line_result,
	count(*) as order_lines,
	round(sum(total_profit),0) as profit
from df_orders
group by case when profit < 0 then 'loss'
	when profit = 0 then 'neutral'
	else 'profit' end;
-- Result: 3,997 lines (42%) lose money, but only about $11K in total,
-- against $1.05M profit on the other 5,490 lines. No break-even lines (every order has a discount).


--3.why do so many lines lose money?
select 
	case when list_price = cost_price then 'list = cost'
		when list_price > cost_price then 'list > cost'
		else 'list < cost' end as price_setup,
	count(*) as order_lines,
	sum(case when profit < 0 then 1 else 0 end) as losing_lines
from dbo.df_orders
group by case when list_price = cost_price then 'list = cost'
		when list_price > cost_price then 'list > cost'
		else 'list < cost' end;
-- Result: list = cost -> 3,955 lines, all losing. list > cost -> 5,532 lines, only 42 losing.
-- Losses come from items with no markup: any discount puts them below cost.

--4.do bigger discounts sell more? 

select 
	discount_percent,
	count(*) as order_lines,
	sum(quantity) as units_sold,
	round(sum(revenue),0) as revenue,
	round(sum(total_profit)* 100.0/sum(revenue),1) as margin_pct
from df_orders
group by discount_percent
order by discount_percent;
-- Result: margin drops from 10.7% (2% discount) to 7.9% (5% discount),
-- while order lines stay about the same (~2,300-2,400 per level). Bigger discounts cut margin without adding volume.

--5. sub-categories under 8% margin (having):
select 
	category,
	sub_category,
	round(sum(revenue),0) as revenue,
	round(sum(total_profit)* 100.0/sum(revenue),1) as margin_pct
from df_orders
group by category,sub_category
having sum(total_profit)* 100.0/sum(revenue) < 8
order by margin_pct;
-- Result: Fasteners 2.7%, Labels 6.1%, Supplies 7.4%, Art 7.9%. All low-price office supplies.

--6.each category's % of the total revenue
with cat as (
select category, sum(revenue)as revenue
from df_orders
group by category
)
select 
	category,
	round(revenue,0)as revenue,
	round(revenue *100.0/sum(revenue) over(), 1) as pct_of_total
from cat
order by revenue desc;
-- Result: Technology 35.5%, Furniture 33.6%, Office Supplies 30.9%. Fairly even split.


--7. top 3 products in each region(rank)

with product_sales as (
select region, product_id, sum(revenue)as revenue
from df_orders
group by region, product_id
),
ranked as (
	select *,
	rank() over(partition by region order by revenue desc) as rnk
	from product_sales
)

select region, product_id, round(revenue,0) as revenue, rnk
from ranked
where rnk <= 3
order by region, rnk;
-- Result: one copier (TEC-CO-10004722) is top 3 in central, east and west. Top sellers are mostly technology.

--8.most profitable sub-category per region
with sub as (
select region, sub_category, sum(total_profit)as profit
from df_orders
group by region, sub_category
),
ranked as (
	select *,
	rank() over (partition by region order by profit desc)as rnk
	from sub
)
select region,sub_category, round(profit,0) as profit
from ranked
where rnk = 1
order by region;
-- Result: chairs lead profit in central and east, machines in south, tables in west.

--9.2022 vs 2023 by month (growth %)

with monthly as (
select year(order_date)as yr,
		month(order_date)as mth,
		sum(revenue)as revenue
from df_orders
group by year(order_date), month(order_date)
),
side_by_side as (
	select mth,
	sum(case when yr = 2022 then revenue else 0 end) as rev_2022,
	sum(case when yr = 2023 then revenue else 0 end) as rev_2023
	from monthly
	group by mth
)
select mth,
	round(rev_2022,0)as rev_2022,
	round(rev_2023,0)as rev_2023,
	round((rev_2023 - rev_2022)*100.0 / rev_2022,1) as growth_pct
	from side_by_side
	order by mth;
-- Result: flat year overall (+2.3%), but big swings: Feb +64.8%, Jun -29.3%, Nov -25.9%.


--10.2023 running total + change from last month

with monthly as (
select month(order_date) as mth, sum(revenue)as revenue
from df_orders
where year(order_date)= 2023
group by month(order_date)
)
select mth, 
	round(revenue,0) as revenue,
	round(sum(revenue) over (order by mth),0) as running_total,
	round(revenue -lag(revenue) over (order by mth),0)as change_vs_last_month
from monthly
order by mth;
-- Result: running total reaches $5.60M in December (= 2023 revenue).