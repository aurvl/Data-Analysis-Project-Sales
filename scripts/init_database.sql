CREATE SCHEMA IF NOT EXISTS gold;

DROP TABLE IF EXISTS gold.fact_sales;
DROP TABLE IF EXISTS gold.dim_products;
DROP TABLE IF EXISTS gold.dim_customers;

CREATE TABLE gold.dim_customers (
    customer_key integer,
    customer_id integer,
    customer_number varchar(50),
    first_name varchar(50),
    last_name varchar(50),
    country varchar(50),
    marital_status varchar(50),
    gender varchar(50),
    birthdate date,
    create_date date
);

CREATE TABLE gold.dim_products (
    product_key integer,
    product_id integer,
    product_number varchar(50),
    product_name varchar(50),
    category_id varchar(50),
    category varchar(50),
    subcategory varchar(50),
    maintenance varchar(50),
    cost integer,
    product_line varchar(50),
    start_date date
);

CREATE TABLE gold.fact_sales (
    order_number varchar(50),
    product_key integer,
    customer_key integer,
    order_date date,
    shipping_date date,
    due_date date,
    sales_amount integer,
    quantity smallint,
    price integer
);

\copy gold.dim_customers FROM 'C:/Users/aurel/Desktop/Projects/Data Analyst/db/gold.dim_customers.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');
\copy gold.dim_products  FROM 'C:/Users/aurel/Desktop/Projects/Data Analyst/db/gold.dim_products.csv'  WITH (FORMAT csv, HEADER true, DELIMITER ',');
\copy gold.fact_sales    FROM 'C:/Users/aurel/Desktop/Projects/Data Analyst/db/gold.fact_sales.csv'    WITH (FORMAT csv, HEADER true, DELIMITER ',');