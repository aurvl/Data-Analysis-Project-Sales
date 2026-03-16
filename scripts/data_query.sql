-- DATA FOR REPORTING

/*
==========================================
For customers
==========================================
*/
CREATE or REPLACE VIEW gold.report_customers as
WITH base_query as (
-- 1. base query to retrieve core columns from tables
	SELECT
		f.order_number,
		f.product_key,
		f.order_date,
		f.sales_amount,
		f.quantity,
		c.customer_key,
		c.customer_number,
		CONCAT(c.first_name, ' ', c.last_name) as customer_name,
		DATE_PART('year', AGE(CURRENT_DATE, c.birthdate))::int as age
	FROM gold.fact_sales f
	LEFT JOIN gold.dim_customers c
		ON c.customer_key = f.customer_key
	WHERE f.order_date IS NOT NULL
),
customer_aggregation as (
	-- 2. We now aggregate the data at the customer level.
	SELECT
		customer_key,
		customer_number,
		customer_name,
		age,
		COUNT(DISTINCT order_number) as total_orders,
		SUM(sales_amount) as total_sales,
		SUM(quantity) as total_quantity,
		COUNT(DISTINCT product_key) as total_products,
		MAX(order_date) as last_order_date,
		(
			DATE_PART('year', MAX(order_date)) - DATE_PART('year', MIN(order_date))
		) * 12 + (
			DATE_PART('month', MAX(order_date)) - DATE_PART('month', MIN(order_date))
		) as lifespan
	FROM base_query
	GROUP BY 
		customer_key,
		customer_number,
		customer_name,
		age
)
SELECT
	-- 3.KPIs
	customer_key,
	customer_number,
	customer_name,
	age,
	CASE
		WHEN age IS NULL THEN 'unknown'
		WHEN age < 20 THEN 'under 20'
		WHEN age BETWEEN 20 AND 29 THEN '20-29'
		WHEN age BETWEEN 30 AND 39 THEN '30-39'
		WHEN age BETWEEN 40 AND 49 THEN '40-49'
		ELSE '50 and above'
	END AS age_group,
	CASE
		WHEN lifespan >= 12 and total_sales > 5000 THEN 'VIP'
		WHEN lifespan >= 12 and total_sales <= 5000 THEN 'Regular'
		ELSE 'New'
	END AS customer_segment,
	last_order_date,
	(
		DATE_PART('month', CURRENT_DATE) - DATE_PART('month', last_order_date)
	) + (
		DATE_PART('year', CURRENT_DATE) - DATE_PART('year', last_order_date)
	) * 12 as recency_in_months,
	total_orders,
	total_sales,
	total_quantity,
	total_products,
	lifespan,
	-- Compute avg order value (AVO)
	CASE
		WHEN total_orders = 0 THEN 0
		ELSE ROUND(total_sales::numeric / total_orders::numeric, 2)
	END AS avg_order_value,
	-- Compute avg monthly spend
	CASE
		WHEN lifespan = 0 THEN total_sales
		ELSE ROUND(total_sales::numeric / lifespan::numeric, 2)
	END AS avg_monthly_spend
FROM customer_aggregation;

SELECT *
FROM gold.report_customers;

--by age
SELECT
	age_group,
	COUNT(customer_number) as total_customers,
	SUM(total_sales) as total_sales
FROM gold.report_customers
GROUP BY age_group;

--by segment
SELECT
	customer_segment,
	COUNT(customer_number) as total_customers,
	SUM(total_sales) as total_sales
FROM gold.report_customers
GROUP BY customer_segment;

/*
==========================================
For products
==========================================
*/
CREATE or REPLACE VIEW gold.report_products as
WITH base_query as (
-- 1. base query to retrieve core columns from tables
	SELECT
		f.order_number,
		f.order_date,
		f.customer_key,
		f.sales_amount,
		f.quantity,
		p.product_key,
		p.product_name,
		p.category,
		p.subcategory,
		p.cost
	FROM gold.fact_sales f
	LEFT JOIN gold.dim_products p
		ON p.product_key = f.product_key
	WHERE f.order_date IS NOT NULL
),
product_aggregation as (
	-- 2. We now aggregate the data at the product level.
	SELECT
		product_key,
		product_name,
		category,
		subcategory,
		cost,
		(
			DATE_PART('year', MAX(order_date)) - DATE_PART('year', MIN(order_date))
		) * 12 + (
			DATE_PART('month', MAX(order_date)) - DATE_PART('month', MIN(order_date))
		) as lifespan,
		MAX(order_date) as last_sale_date,
		COUNT(DISTINCT order_number) as total_orders,
		COUNT(DISTINCT customer_key) as total_customers,
		SUM(sales_amount) as total_sales,
		SUM(quantity) as total_quantity,
		ROUND(AVG(sales_amount::numeric(10, 2) / NULLIF(quantity, 0)), 2) as avg_selling_price
	FROM base_query
	GROUP BY 
		product_key,
		product_name,
		category,
		subcategory,
		cost
)
SELECT
	-- 3.KPIs
	product_key,
	product_name,
	category,
	subcategory,
	cost,
	last_sale_date,
	(
		DATE_PART('month', CURRENT_DATE) - DATE_PART('month', last_sale_date)
	) + (
		DATE_PART('year', CURRENT_DATE) - DATE_PART('year', last_sale_date)
	) * 12 as recency_in_months,
	CASE
		WHEN total_sales > 50000 THEN 'High-Performer'
		WHEN total_sales >= 10000 THEN 'Mid-Performer'
		ELSE 'Low-Performer'
	END AS product_segment,
	lifespan,
	total_orders,
	total_sales,
	total_quantity,
	total_customers,
	avg_selling_price,
	-- avg order revenue
	CASE
		WHEN total_orders = 0 THEN 0
		ELSE ROUND(total_sales::numeric / total_orders::numeric, 2)
	END AS avg_order_revenue,
	-- avg monthly revenue
	CASE
		WHEN lifespan = 0 THEN total_sales
		ELSE ROUND(total_sales::numeric / lifespan::numeric, 2)
	END AS avg_monthly_revenue
FROM product_aggregation;

SELECT *
FROM gold.report_products;


/*
==========================================
Global
==========================================
*/
CREATE or REPLACE VIEW gold.report_overview as
WITH customer_base as (
    SELECT
        f.customer_key,
        c.customer_number,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        DATE_PART('year', AGE(CURRENT_DATE, c.birthdate))::int as age,
        MIN(f.order_date) as first_order_date,
        MAX(f.order_date) as last_order_date,
        SUM(f.sales_amount) as customer_total_sales
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_customers c
        ON c.customer_key = f.customer_key
    WHERE f.order_date IS NOT NULL
    GROUP BY
        f.customer_key,
        c.customer_number,
        c.first_name,
        c.last_name,
        c.birthdate
),
customer_segments as (
    SELECT
        customer_key,
        customer_number,
        customer_name,
        age,
        CASE
            WHEN age IS NULL THEN 'unknown'
            WHEN age < 20 THEN 'under 20'
            WHEN age between 20 and 29 THEN '20-29'
            WHEN age between 30 and 39 THEN '30-39'
            WHEN age between 40 and 49 THEN '40-49'
            ELSE '50 and above'
        END AS age_group,
        first_order_date,
        last_order_date,
        customer_total_sales,
        (
            (DATE_PART('year', last_order_date) - DATE_PART('year', first_order_date)) * 12
            + (DATE_PART('month', last_order_date) - DATE_PART('month', first_order_date))
        )::int AS lifespan,
        CASE
            WHEN (
                (DATE_PART('year', last_order_date) - DATE_PART('year', first_order_date)) * 12
                + (DATE_PART('month', last_order_date) - DATE_PART('month', first_order_date))
            ) >= 12
            AND customer_total_sales > 5000 THEN 'VIP'
            WHEN (
                (DATE_PART('year', last_order_date) - DATE_PART('year', first_order_date)) * 12
                + (DATE_PART('month', last_order_date) - DATE_PART('month', first_order_date))
            ) >= 12
            AND customer_total_sales <= 5000 THEN 'Regular'
            ELSE 'New'
        END AS customer_segment
    FROM customer_base
)
SELECT
    f.order_number,
    f.order_date,
    DATE_TRUNC('month', f.order_date)::date as order_month,
    DATE_PART('year', f.order_date)::int as order_year,
    DATE_PART('month', f.order_date)::int as order_month_num,

    f.customer_key,
    cs.customer_number,
    cs.customer_name,
    cs.age,
    cs.age_group,
    cs.customer_segment,
    cs.first_order_date,
    cs.last_order_date,
    cs.lifespan as customer_lifespan_months,
    (
        (DATE_PART('year', CURRENT_DATE) - DATE_PART('year', cs.last_order_date)) * 12
        + (DATE_PART('month', CURRENT_DATE) - DATE_PART('month', cs.last_order_date))
    )::int as customer_recency_in_months,

    f.product_key,
    p.product_name,
    p.category,
    p.subcategory,
    p.cost,

    f.sales_amount,
    f.quantity,
    CASE
        WHEN f.quantity = 0 THEN NULL
        ELSE ROUND((f.sales_amount::numeric / f.quantity::numeric), 2)
    END AS unit_selling_price,

    CASE
        WHEN p.cost IS NULL THEN NULL
        ELSE ROUND((f.sales_amount - (p.cost * f.quantity))::numeric, 2)
    END AS gross_profit_estimate
FROM gold.fact_sales f
LEFT JOIN customer_segments cs
    ON cs.customer_key = f.customer_key
LEFT JOIN gold.dim_products p
    ON p.product_key = f.product_key
WHERE f.order_date IS NOT NULL;

SELECT *
FROM gold.report_overview
LIMIT 10;

SELECT
    order_month,
    SUM(sales_amount) AS total_sales
FROM gold.report_overview
GROUP BY order_month
ORDER BY order_month;

SELECT
    customer_segment,
    age_group,
    SUM(sales_amount) AS total_sales
FROM gold.report_overview
GROUP BY customer_segment, age_group
ORDER BY customer_segment, age_group;


-- end