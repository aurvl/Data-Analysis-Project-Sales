-- CHANGE OVER TIME
-- Objective: Analyze business trends and cumulative performance over time.

-- Sales performance over the years
SELECT
	-- extract the year from dates
	DATE_PART('year', order_date) as order_year,
	-- or: EXTRACT(YEAR FROM order_date) as order_year,
	SUM(sales_amount) as total_sales,
	COUNT(DISTINCT customer_key) as total_customers,
	SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY order_year
ORDER BY order_year;
-- 2023 recorded the highest sales revenue, making it the best year for the business.

-- Sales performance over the months
SELECT
	DATE_PART('month', order_date) as order_month,
	SUM(sales_amount) as total_sales,
	COUNT(DISTINCT customer_key) as total_customers,
	SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY order_month
ORDER BY order_month;
-- December shows the highest activity due to holiday events such as Christmas and end-of-year celebrations.

-- Sales performance over the years and months
SELECT
	DATE_PART('year', order_date) as order_year,
	DATE_PART('month', order_date) as order_month,
	SUM(sales_amount) as total_sales,
	COUNT(DISTINCT customer_key) as total_customers,
	SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY order_year, order_month
ORDER BY order_year, order_month;
--or:
SELECT
    TO_CHAR(DATE_TRUNC('month', order_date), 'YYYY-MM') as order_month,
    SUM(sales_amount) as total_sales,
    COUNT(DISTINCT customer_key) as total_customers,
    SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY order_month
ORDER BY order_month;


-- CUMULATIVE AND PERFORMANCE ANALYSIS
-- Total sales per month
SELECT 
    order_month,
    total_sales,
    SUM(total_sales) OVER (ORDER BY order_month) as cumul_total_sales,
    ROUND(AVG(avg_price) OVER (ORDER BY order_month), 2) as moving_avg_price
FROM (
    SELECT
        TO_CHAR(DATE_TRUNC('month', order_date), 'YYYY-MM') as order_month,
        SUM(sales_amount) as total_sales,
        AVG(price) as avg_price
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY order_month
) t;

-- Yearly perf of the business (products by sales)
WITH yps as (
	WITH yearly_product_sales as (
		SELECT
			DATE_PART('year', f.order_date) as order_year,
			p.product_name,
			SUM(f.sales_amount) as current_sales
		FROM gold.fact_sales f
		LEFT JOIN gold.dim_products p
			ON f.product_key = p.product_key
		WHERE f.order_date IS NOT NULL
		GROUP BY order_year, p.product_name
	)
	SELECT 
		order_year,
		product_name,
		current_sales,
		ROUND(AVG(current_sales) OVER (PARTITION BY product_name), 2) as avg_sales,
		ROUND(current_sales - AVG(current_sales) OVER (PARTITION BY product_name), 2) as diff_avg
	FROM yearly_product_sales
	ORDER BY product_name
)
SELECT *,
	CASE WHEN diff_avg > 0 THEN 'Above Avg'
		  WHEN diff_avg < 0 THEN 'Below Avg'
		  ELSE 'Avg'
	END avg_change,*
	-- Year over year analysis
	CASE WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase'
		  WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
		  ELSE 'No change'
	END previous_year_change
FROM yps;


--BUSINESS DRIVERS
-- Part to whole analysis
WITH cs as (
	WITH category_sales as (
		SELECT
			category,
			SUM(sales_amount) as total_sales
		FROM gold.fact_sales f
		LEFT JOIN gold.dim_products p
			ON p.product_key = f.product_key
		GROUP BY category
	)
	SELECT
		category,
		total_sales,
		SUM(total_sales) OVER () overall_sales
	FROM category_sales
)
SELECT *,
	CONCAT(ROUND(total_sales / overall_sales * 100, 2), '%') as pct_of_total
FROM cs;
-- Bikes is the category that drives the business.


-- DATA SEGMENTATION
-- Product segmentation
WITH product_segment as (
	SELECT
		product_key,
		product_name,
		cost,
		CASE WHEN cost < 100 THEN 'Below 100'
			  WHEN cost BETWEEN 100 and 500 THEN '100-500'
			  WHEN cost BETWEEN 500 and 1000 THEN '500-1000'
			  ELSE 'Above 1000'
		END cost_range
	FROM gold.dim_products
)
SELECT
	cost_range,
	COUNT(product_key) as total_products
FROM product_segment
GROUP BY cost_range
ORDER BY total_products DESC;


-- Customers segmentation
WITH cust_hist as (
	SELECT
		customer_key,
		MIN(order_date) as first_order,
		MAX(order_date) as last_order
	FROM gold.fact_sales
	GROUP BY customer_key
)
SELECT
	customer_key,
	AGE(last_order, first_order) AS customer_duration
FROM cust_hist;


WITH customer_spend as (
	SELECT 
		c.customer_key,
		SUM(f.sales_amount) as total_spending,
		MIN(order_date) as first_order,
		MAX(order_date) as last_order,
		-- month interval between first and last order
		(DATE_PART('year', MAX(order_date)) - DATE_PART('year', MIN(order_date))) * 12
		+ (DATE_PART('month', MAX(order_date)) - DATE_PART('month', MIN(order_date))) as lifespan
	FROM gold.fact_sales f
	LEFT JOIN gold.dim_customers c
		ON f.customer_key = c.customer_key
	GROUP BY c.customer_key
)
SELECT
	customer_segment,
	COUNT(customer_key) as total_customers
FROM (
	SELECT
		customer_key,
		-- total_spending,
		-- lifespan,
		CASE WHEN lifespan >= 12 and total_spending > 5000 THEN 'VIP'
			  WHEN lifespan >= 12 and total_spending <= 5000 THEN 'Regular'
			  ELSE 'New'
		END customer_segment
	FROM customer_spend ) t
GROUP BY customer_segment
ORDER BY total_customers DESC;
