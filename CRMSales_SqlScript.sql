#We will perform Cleaning and EDA steps on each table, and combined them later as needed for analysis

CREATE DATABASE CRM_Sales; #Creating new database
USE CRM_Sales;

DROP TABLE data_dictionary; #Dropping data_dictionary table as we do not required at this moment

##Let's explore sales_pipeline table as it is our main table
SELECT * FROM sales_pipeline;
SELECT COUNT(*),COUNT(DISTINCT(opportunity_id)) FROM sales_pipeline;
#Observation: We have 8800 total rows and 8800 unique opportunity_ids, so we can conclude that each contains data of a single opportunity

SELECT DISTINCT deal_stage FROM sales_pipeline;
#As there are some deals still on prospecting and engaging stages, we will include only qualified deals, means leads that have completed the sales process, providing a clearer picture of the efficiency of the sales efforts.
#lets create a new table with only Won and Lost deals

SELECT COUNT(*) FROM sales_pipeline 
WHERE deal_stage IN ('Won','Lost');
#6711 rows 

CREATE TABLE completed_deals
SELECT * FROM sales_pipeline 
WHERE deal_stage IN ('Won','Lost');

##Data Cleaning
DESC completed_deals;
# we need to change engage_date and close_date colums to date type
ALTER TABLE completed_deals
MODIFY COLUMN engage_date DATE,
MODIFY COLUMN close_date DATE;

#lets check text columns
SELECT DISTINCT sales_agent FROM completed_deals; #seems there are no inconsistencies in the text
SELECT DISTINCT product FROM completed_deals;

ALTER TABLE completed_deals
ADD COLUMN sale_cycle_duration INT;

UPDATE completed_deals
SET sale_cycle_duration = DATEDIFF(close_date,engage_date);

SELECT * FROM completed_deals;

## Lets explore sales_teams table
SELECT * FROM sales_teams;

SELECT manager, regional_office
FROM sales_teams
GROUP BY 1,2
order by 1;
#Observation: there are 6 teams
#lets add team_id column(agents with same manager will be treated as same team)

ALTER TABLE sales_teams
ADD COLUMN team_id INT;

UPDATE sales_teams AS t1
JOIN (
    SELECT manager, dense_rank() OVER(ORDER BY manager) AS team_id
    FROM sales_teams
) AS t2 ON t1.manager = t2.manager
SET t1.team_id = t2.team_id;

##Lets explore products table
#before joining we need to make sure the product and sales rep names are matching with values products, sales teams tables or if there are any spelling errors
SELECT * FROM products;

SELECT distinct product FROM completed_deals ORDER BY 1;
SELECT product FROM products ORDER BY 1;
# GTXPro has space in product table where as completed_deals table doesn't have, so we need to modify this
UPDATE completed_deals
SET product = replace(product,'GTXPro','GTX Pro');

#lets join these three tables, as of now we won't use accounts table as its not required for our analysis
CREATE TABLE final_table
SELECT c.*, s.manager,s.regional_office,s.team_id,p.series,p.sales_price 
FROM completed_deals c
JOIN sales_teams s
ON c.sales_agent = s.sales_agent
JOIN products p
ON c.product = p.product;

SELECT * FROM final_table;
#lets add additional columns 
#1. Sales Variance, 2. sales_variance_status

#Lets add them as columns in our original table 
ALTER TABLE final_table
ADD COLUMN quarter INT,
ADD COLUMN sales_variance INT,
ADD COLUMN sales_variance_status VARCHAR(20); 

UPDATE final_table
SET 
quarter = quarter(close_date),
sales_variance = close_value-sales_price,
sales_variance_status = 
CASE 
	WHEN sales_variance<0 THEN 'Negative Variance'
    WHEN sales_variance IS null THEN null
    ELSE 'Positive Variance'
END;

SELECT * FROM final_table;


#1.) How is each sales team performing compared to the rest?

CREATE TABLE sales_team_metrics
SELECT 
    team_id,
    #1
    COUNT(opportunity_id) AS total_completed_deals,
	#2
    ROUND(SUM(CASE WHEN deal_stage = 'Won' THEN 1 ELSE 0 END)*1.0/COUNT(*),4) AS won_deals_proportion,
    #3
    ROUND(AVG(sale_cycle_duration),4) AS average_sale_cycle_duration,
    #4
    ROUND(SUM(CASE WHEN sales_variance_status = 'Positive Variance' THEN 1 ELSE 0 END)*1.0/COUNT(*),4) AS positive_var_proportion
FROM final_table
GROUP BY team_id
ORDER BY team_id;

SELECT * FROM sales_team_metrics;

#2. •	Are any sales agents lagging behind?
CREATE TABLE sales_agent_metrics
SELECT 
    sales_agent,
    #1
    COUNT(opportunity_id) AS total_completed_deals,
	#2
    ROUND(SUM(CASE WHEN deal_stage = 'Lost' THEN 1 ELSE 0 END)*1.0/COUNT(*),4) AS lost_deals_proportion,
    #3
	ROUND(AVG(sale_cycle_duration),4) AS average_sale_cycle_duration,
    #4
    ROUND(SUM(CASE WHEN sales_variance_status = 'Negative Variance' THEN 1 ELSE 0 END)*1.0/COUNT(*),4) AS negative_var_proportion
FROM final_table
GROUP BY sales_agent
ORDER BY sales_agent;

SELECT * FROM sales_agent_metrics;


#3.•Can you identify any quarter-over-quarter trends?
SELECT MIN(close_date), MAX(close_date),min(engage_date),max(engage_date) FROM final_table;
#deals closed from March 2017 to Dec 2017

WITH table1 AS (SELECT 
				quarter,
				COUNT(*) AS closed_deals,
				LAG(COUNT(*)) OVER (ORDER BY quarter) AS previous_deals,
                SUM(close_value) AS total_close_value,
                LAG(SUM(close_value)) OVER (ORDER BY quarter) AS previous_close_value,
                ROUND(SUM(CASE WHEN deal_stage = 'Won' THEN 1 ELSE 0 END)*1.0/COUNT(*),2) AS won_deals_proportion
				FROM final_table
				WHERE close_date IS NOT NULL
				GROUP BY quarter)
SELECT quarter,
(closed_deals-previous_deals)/previous_deals AS `closed_deals_growth(%)`,
(total_close_value-previous_close_value)/previous_close_value AS `revenue_from_closed_deals(%)`
FROM table1;


#4. •	Do any products have better win rates? 
SELECT  product,
ROUND(SUM(CASE WHEN deal_stage = 'Won' THEN 1 ELSE 0 END)*1.0/COUNT(*),4) AS won_deals_proportion
FROM final_table
WHERE deal_stage IN('Won', 'Lost') #from closed deals only
GROUP BY product
ORDER BY 2 DESC;

