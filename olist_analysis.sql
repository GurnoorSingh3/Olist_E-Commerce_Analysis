-- ============================================
--         OLIST E-COMMERCE ANALYSIS
-- ============================================

-- 1. SALES PERFORMANCE

-- Monthly delivered sales

SELECT
    DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
    ROUND(SUM(oi.price)::numeric, 2) AS monthly_delivered_sales
FROM orders_clean_python AS o
JOIN order_items_clean_python AS oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY month
ORDER BY month;

-- Monthly delivered order volume

SELECT
    DATE_TRUNC('month', order_purchase_timestamp) AS month,
    COUNT(DISTINCT order_id) AS delivered_orders
FROM orders_clean_python
WHERE order_status = 'delivered'
GROUP BY month
ORDER BY month;

-- Monthly Average Order Value

WITH order_totals AS (
    SELECT
        o.order_id,
        DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
        SUM(oi.price) AS order_value
    FROM orders_clean_python AS o
    JOIN order_items_clean_python AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY
        o.order_id,
        DATE_TRUNC('month', o.order_purchase_timestamp)
)
SELECT
    month,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(order_value)::numeric, 2) AS average_order_value
FROM order_totals
GROUP BY month
ORDER BY month;

-- Monthly revenue growth

WITH monthly_sales AS (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
        SUM(oi.price) AS monthly_sales
    FROM orders_clean_python AS o
    JOIN order_items_clean_python AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY month
)
SELECT
    month,
    ROUND(monthly_sales::numeric, 2) AS monthly_sales,
    ROUND(
		(
		 (monthly_sales - lag(monthly_sales) over (order by month)) / 
		 nullif(lag(monthly_sales) over (order by month) , 0 ) * 100
		) :: numeric , 2
	) AS month_over_month_growth_pct
FROM monthly_sales
ORDER BY month;

-- 2. PRODUCT PERFORMANCE

-- Revenue by product category

select 
	coalesce(
		ct.product_category_name_english ,
		p.product_category_name ,
		'unknown'
	) as product_category ,
	round(sum(oi.price)::numeric , 2) as delivered_sales
from orders_clean_python as o
join order_items_clean_python as oi on o.order_id = oi.order_id
join products_clean_python as p on oi.product_id = p.product_id
left join category_translation_clean_python as ct on p.product_category_name = ct.product_category_name
group by product_category
order by delivered_sales desc ;

-- Category contribution

SELECT
    p.product_category_name,
    ct.product_category_name_english,
    COUNT(*) AS product_count
FROM products_clean_python AS p
LEFT JOIN category_translation_clean_python AS ct
    ON p.product_category_name = ct.product_category_name
GROUP BY
    p.product_category_name,
    ct.product_category_name_english
ORDER BY p.product_category_name;

-- Category order/item metrics

select 
	coalesce(
		ct.product_category_name_english ,
		p.product_category_name ,
		'unknown'
	) as product_category ,
	round(sum(oi.price)::numeric , 2) as delivered_sales ,
	count(*) as item_count ,
	count(distinct o.order_id) as order_conunt ,
	round((sum(oi.price)::numeric) / count(*) , 2) as avg_item_price ,
	round((sum(oi.price)::numeric) / count(distinct o.order_id) , 2) as revenue_per_category_item
from orders_clean_python as o
join order_items_clean_python as oi on o.order_id = oi.order_id
join products_clean_python as p on oi.product_id = p.product_id
left join category_translation_clean_python as ct on p.product_category_name = ct.product_category_name
group by product_category
order by delivered_sales desc ;

-- Category order/item metrics pct

with category_sales as (
	select 
		coalesce(
			ct.product_category_name_english ,
			p.product_category_name ,
			'unknown'
		) as product_category ,
		round(sum(oi.price)::numeric , 2) as delivered_sales ,
		count(*) as item_count ,
		count(distinct o.order_id) as order_count ,
		round((sum(oi.price)::numeric) / count(*) , 2) as avg_item_price ,
		round((sum(oi.price)::numeric) / count(distinct o.order_id) , 2) as revenue_per_category_item
	from orders_clean_python as o
	join order_items_clean_python as oi on o.order_id = oi.order_id
	join products_clean_python as p on oi.product_id = p.product_id
	left join category_translation_clean_python as ct on p.product_category_name = ct.product_category_name
	group by product_category
) 
select 
    product_category,
    ROUND(delivered_sales::numeric, 2) AS delivered_sales,
    item_count,
    order_count,
    ROUND(
        (delivered_sales / NULLIF(item_count, 0))::numeric,
        2
    ) AS avg_item_price,
    ROUND(
        (delivered_sales / NULLIF(order_count, 0))::numeric,
        2
    ) AS revenue_per_order,
    ROUND(
        (
            delivered_sales
            / NULLIF(SUM(delivered_sales) OVER (), 0)
            * 100
        )::numeric,
        2
    ) AS revenue_contribution_pct
FROM category_sales
ORDER BY delivered_sales DESC;

-- 3. CUSTOMER BEHAVIOR

-- One-time vs repeat customers

with customer_orders as (
	select 
	c.customer_unique_id ,
	count(distinct o.order_id) as order_count
	from customers_clean_python as c
	join orders_clean_python as o on c.customer_id = o.customer_id
	where order_status = 'delivered'
	group by c.customer_unique_id
)
select 
	case 
		when order_count = 1 then 'One-time Customer'
		else 'Repeating Customers'
	end as customer_type,
	count(*) as customer_count, 
	round(
		count(*) * 100.0 / sum(count(*)) over(),
		2
	) as customer_pct
from customer_orders
group by customer_type
order by customer_pct desc;

-- Customer revenue contribution

with customer_order_summary as (
	select 
		c.customer_unique_id ,
		count(*) as order_count
	from customers_clean_python as c 
	join orders_clean_python as o 
		on c.customer_id = o.customer_id
	where o.order_status = 'delivered'
	group by c.customer_unique_id
),
customer_revenue as (
	select 
		c.customer_unique_id ,
		sum(oi.price) as customer_sales
	from customers_clean_python as c 
	join orders_clean_python as o 
		on c.customer_id = o.customer_id
	join order_items_clean_python as oi 
		on o.order_id = oi.order_id
	where o.order_status = 'delivered'
	group by c.customer_unique_id 
)
select 
	case when order_count = 1 then 'One-time Customer'
		else 'Repeating Customers'
	end as customer_type ,
	count(*) as customer_count, 
	round(sum(r.customer_sales ):: numeric , 2) as total_sales,
	round(avg(r.customer_sales ):: numeric , 2) as avg_customer_sales,
	round(
		sum(r.customer_sales) :: numeric / 
		nullif(sum(sum(r.customer_sales):: numeric ) over() ,0) * 100,
		2
	) as sales_contribution_pct
from customer_order_summary as os
join customer_revenue as r 
	on os.customer_unique_id = r.customer_unique_id
group by customer_type
order by sales_contribution_pct desc;

-- Order frequency

with customer_orders as (
	select 
	c.customer_unique_id ,
	count(distinct o.order_id) as order_count
	from customers_clean_python as c
	join orders_clean_python as o on c.customer_id = o.customer_id
	where order_status = 'delivered'
	group by c.customer_unique_id
)
select 
	case when order_count >= 5 then '5+ orders'
		else order_count :: text
	end as Order_frequency ,
	count(*) as Customer_count,
	round(
		count(*) * 100.0 / sum(count(*)) over() , 2
	) as customer_pct
from customer_orders
group by 
	case when order_count >= 5 then '5+ orders'
		else order_count :: text
	end
order by 
	case when order_count >= 5 then '5+ orders'
		else order_count :: text
	end;

-- 4. DELIVERY PERFORMANCE

-- Average delivery time by month

with delivery_data as (
	select 
		order_id ,
		date_trunc('month' , order_purchase_timestamp) as month ,
		order_purchase_timestamp ,
		order_delivered_customer_date - order_purchase_timestamp as delivery_duration
	from orders_clean_python
	where order_status = 'delivered'
		and order_delivered_customer_date is not null
		and order_delivered_customer_date >= order_purchase_timestamp
)
select 
	month ,
	count(*) as delivered_orders ,
	round( avg(extract(epoch from delivery_duration) / 86400) :: numeric , 2)
from delivery_data
group by month 
order by month ;
	
-- Late delivery pct

WITH delivery_performance AS (
    SELECT
        order_id,
        CASE
            WHEN order_delivered_customer_date
                 > order_estimated_delivery_date
            THEN 1
            ELSE 0
        END AS delivered_late
    FROM orders_clean_python
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
      AND order_delivered_customer_date >= order_purchase_timestamp
)
SELECT
    COUNT(*) AS valid_delivered_orders,
    SUM(delivered_late) AS late_orders,
    COUNT(*) - SUM(delivered_late) AS on_time_orders,
    ROUND(
        SUM(delivered_late) * 100.0 / COUNT(*), 2
    ) AS late_delivery_percentage
FROM delivery_performance;
	
-- delivery time review corelation

with delivery_review as (
	select 
		o.order_id ,
		r.review_score ,
		case
			when o.order_delivered_customer_date 
				> o.order_estimated_delivery_date
			then 'late'
			else 'on time'
		end as delivery_status
	from orders_clean_python as o
	join reviews_clean_python as r on o.order_id = r.order_id	
	WHERE order_status = 'delivered'
      	AND order_delivered_customer_date IS NOT NULL
      	AND order_estimated_delivery_date IS NOT NULL
      	AND order_delivered_customer_date >= order_purchase_timestamp
)
select 
	delivery_status,
	count(*) as delivered_orders,
	round(avg(review_score):: numeric , 2) as avg_review
from delivery_review
group by delivery_status;

-- State-wise performance

select 
	c.customer_state,
	round(sum(oi.price)::numeric , 2) as delivered_sales,
	count(distinct o.order_id) as delivered_orders,
	count(distinct c.customer_unique_id) as total_customers,
	round(
		sum(oi.price)::numeric /
		nullif(count(distinct o.order_id) , 0) * 100 
		, 2
	) as sales_per_order
from orders_clean_python as o
join customers_clean_python as c
	on o.customer_id = c.customer_id
join order_items_clean_python as oi 
	on o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
group by c.customer_state
order by round(sum(oi.price)::numeric , 2) desc;

-- Delivery Performance

WITH delivery_data AS (
    SELECT
        o.order_id,
        c.customer_state,
        EXTRACT(
            EPOCH FROM (
                o.order_delivered_customer_date
                - o.order_purchase_timestamp
            )
        ) / 86400 AS delivery_days,
        CASE
            WHEN o.order_delivered_customer_date
                 > o.order_estimated_delivery_date
            THEN 1
            ELSE 0
        END AS delivered_late
    FROM orders_clean_python AS o
    JOIN customers_clean_python AS c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
      AND o.order_delivered_customer_date >= o.order_purchase_timestamp
)
SELECT
    customer_state,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(delivery_days)::numeric, 2)
        AS average_delivery_days,
    SUM(delivered_late) AS late_orders,
    ROUND(
        SUM(delivered_late) * 100.0 / COUNT(*),
        2
    ) AS late_delivery_percentage
FROM delivery_data
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY late_delivery_percentage DESC;

-- CUSTOMER EXPERIENCE

-- Revenue and review score together

WITH category_sales AS (
    SELECT
        p.product_category_name,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        ) AS product_category,
        SUM(oi.price) AS delivered_sales
    FROM orders_clean_python AS o
    JOIN order_items_clean_python AS oi
        ON o.order_id = oi.order_id
    JOIN products_clean_python AS p
        ON oi.product_id = p.product_id
    LEFT JOIN category_translation_clean_python AS ct
        ON p.product_category_name = ct.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY
        p.product_category_name,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        )
),
category_reviews AS (
    SELECT
        p.product_category_name,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        ) AS product_category,
        COUNT(*) AS review_count,
        AVG(r.review_score) AS average_review_score
    FROM orders_clean_python AS o
    JOIN order_items_clean_python AS oi
        ON o.order_id = oi.order_id
    JOIN products_clean_python AS p
        ON oi.product_id = p.product_id
    JOIN reviews_clean_python AS r
        ON o.order_id = r.order_id
    LEFT JOIN category_translation_clean_python AS ct
        ON p.product_category_name = ct.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY
        p.product_category_name,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        )
)
SELECT
    s.product_category,
    ROUND(s.delivered_sales::numeric, 2)
        AS delivered_sales,
    r.review_count,
    ROUND(r.average_review_score::numeric, 2)
        AS average_review_score
FROM category_sales AS s
LEFT JOIN category_reviews AS r
    ON s.product_category = r.product_category
ORDER BY s.delivered_sales DESC;








