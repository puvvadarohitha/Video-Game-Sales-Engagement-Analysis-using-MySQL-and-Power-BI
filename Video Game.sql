# --- DATABASE SETUP ----

Create database video_games;
Use video_games;

# 2. ---- TABLE CREATION ----

# ---- Table Creation ----
CREATE TABLE games (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255),
    release_date VARCHAR(100),
    team TEXT,
    rating FLOAT,
    times_listed VARCHAR(50),
    number_of_reviews VARCHAR(50),
    genres TEXT,
    summary TEXT,
    reviews LONGTEXT,
    plays VARCHAR(50),
    playing VARCHAR(50),
    backlogs VARCHAR(50),
    wishlist VARCHAR(50),
    release_year VARCHAR(10),
    title_canon VARCHAR(255)
);

# ---- Table 2 : Sales Data ----

CREATE TABLE vgsales (
    rank_id       INT,
    name          VARCHAR(200),
    platform      VARCHAR(50),
    year          INT,
    genre         VARCHAR(50),
    publisher     VARCHAR(100),
    na_sales      DECIMAL(10,2),
    eu_sales      DECIMAL(10,2),
    jp_sales      DECIMAL(10,2),
    other_sales   DECIMAL(10,2),
    global_sales  DECIMAL(10,2),
    name_canon    VARCHAR(200)
);

# ---- Load Data -----

LOAD DATA LOCAL INFILE 'C:/Users/puvva/Downloads/games_cleaned.csv'
INTO TABLE games
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(@col1, title, release_date, team, rating, times_listed, 
number_of_reviews, genres, summary, reviews, plays, 
playing, backlogs, wishlist, release_year, title_canon)
SET id = @col1;

# ---- load sales dataset ---- 

LOAD DATA LOCAL INFILE 'C:/Users/puvva/Downloads/vgsales_cleaned.csv'
INTO TABLE vgsales
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(rank_id, name, platform, year, genre, publisher, 
na_sales, eu_sales, jp_sales, other_sales, global_sales, name_canon);

-- Verify row counts
SELECT 'games'   AS table_name, COUNT(*) AS total_rows FROM games
UNION ALL
SELECT 'vgsales' AS table_name, COUNT(*) AS total_rows FROM vgsales;

-- ============================================================
-- STEP 4 : DATA CLEANING
-- ============================================================

SET SQL_SAFE_UPDATES = 0;

-- ── games table cleaning ──────────────────────────────────

-- 1. Fix genres list format: ['Action','RPG'] → Action, RPG
UPDATE games
SET genres = REPLACE(REPLACE(REPLACE(REPLACE(
    genres, "['", ''), "']", ''), "', '", ', '), '"', '')
WHERE genres LIKE "[%" OR genres LIKE '"%';
 
-- 2. Fix 3 empty genre rows
UPDATE games
SET genres = 'Unknown'
WHERE id IN (713, 1309, 1475);
 
-- 3. Fix times_listed: remove commas from numbers
UPDATE games
SET times_listed = REPLACE(times_listed, ',', '')
WHERE times_listed LIKE '%,%';
 
-- 4. Fix number_of_reviews: remove commas from numbers
UPDATE games
SET number_of_reviews = REPLACE(number_of_reviews, ',', '')
WHERE number_of_reviews LIKE '%,%';
 
-- 5. Fill missing plays with median
UPDATE games
SET plays = NULL
WHERE plays = '' OR plays = '0';

UPDATE games
SET plays = (
    SELECT med FROM (
        SELECT ROUND(AVG(CAST(plays AS DECIMAL(10,2))), 2) AS med
        FROM games
        WHERE plays IS NOT NULL AND plays != ''
    ) AS sub
)
WHERE plays IS NULL;

-- 6. Fix blank backlogs → Fill With Median
UPDATE games
SET backlogs = NULL
WHERE backlogs = '' OR backlogs = '0';

UPDATE games
SET backlogs = (
    SELECT med FROM (
        SELECT ROUND(AVG(CAST(backlogs AS DECIMAL(10,2))), 2) AS med
        FROM games
        WHERE backlogs IS NOT NULL AND backlogs != ''
    ) AS sub
)
WHERE backlogs IS NULL;

-- 7. Fix blank wishlist → Fill with Median
UPDATE games
SET wishlist = NULL
WHERE wishlist = '' OR wishlist = '0';

UPDATE games
SET wishlist = (
    SELECT med FROM (
        SELECT ROUND(AVG(CAST(wishlist AS DECIMAL(10,2))), 2) AS med
        FROM games
        WHERE wishlist IS NOT NULL AND wishlist != ''
    ) AS sub
)
WHERE wishlist IS NULL;

-- 8. Fix title_canon: clean punctuation for better JOIN matching
UPDATE games
SET title_canon = LOWER(
    TRIM(
        REGEXP_REPLACE(
            REGEXP_REPLACE(title, '[^a-zA-Z0-9 ]', ' '),
        '\\s+', ' ')
    )
);

 -- ── vgsales table cleaning ────────────────────────────────
 
-- 9. Fix missing publisher
UPDATE vgsales
SET publisher = 'Unknown'
WHERE publisher IS NULL OR publisher = '';

-- 10. Fix missing year → set to NULL
UPDATE vgsales
SET year = NULL
WHERE year = 0;

-- Fill missing years with median year
UPDATE vgsales
SET year = (
    SELECT med_year FROM (
        SELECT ROUND(AVG(year)) AS med_year
        FROM vgsales
        WHERE year IS NOT NULL
    ) AS sub
)
WHERE year IS NULL;

-- Verify → should show 0
SELECT 
    SUM(CASE WHEN year IS NULL THEN 1 ELSE 0 END) AS missing_year
FROM vgsales;

-- 11. Fix name_canon: rebuild properly to fix slash issues
--     e.g. "pokemon redpokemon blue" → "pokemon red pokemon blue"
UPDATE vgsales
SET name_canon = LOWER(
    TRIM(
        REGEXP_REPLACE(
            REGEXP_REPLACE(name, '[^a-zA-Z0-9 ]', ' '),
        '\\s+', ' ')
    )
);

SET SQL_SAFE_UPDATES = 1;
 
-- Add primary_genre column ──────────────────────────────
ALTER TABLE games
ADD COLUMN primary_genre VARCHAR(100);
 
SET SQL_SAFE_UPDATES = 0;
UPDATE games
SET primary_genre = TRIM(SUBSTRING_INDEX(genres, ',', 1));
SET SQL_SAFE_UPDATES = 1;

-- ============================================================
-- STEP 5 : DATA VALIDATION
-- ============================================================

-- Final clean check: all should show 0
SELECT
    COUNT(*)                                                       AS total_rows,
    SUM(CASE WHEN genres LIKE "[%"          THEN 1 ELSE 0 END)    AS bad_genres,
    SUM(CASE WHEN plays    IS NULL          THEN 1 ELSE 0 END)    AS missing_plays,
    SUM(CASE WHEN backlogs IS NULL          THEN 1 ELSE 0 END)    AS missing_backlogs,
    SUM(CASE WHEN wishlist IS NULL          THEN 1 ELSE 0 END)    AS missing_wishlist,
    SUM(CASE WHEN rating   IS NULL          THEN 1 ELSE 0 END)    AS missing_rating
FROM games;

-- Final clean check for vgsales
SELECT
    COUNT(*)                                                            AS total_rows,
    SUM(CASE WHEN year      IS NULL           THEN 1 ELSE 0 END)       AS missing_year,
    SUM(CASE WHEN publisher = 'Unknown'       THEN 1 ELSE 0 END)       AS unknown_publisher,
    SUM(CASE WHEN global_sales IS NULL        THEN 1 ELSE 0 END)       AS missing_sales
FROM vgsales;

-- Check JOIN match count
SELECT
    COUNT(*)                                                            AS total_vgsales,
    SUM(CASE WHEN g.title_canon IS NOT NULL   THEN 1 ELSE 0 END)       AS matched_games,
    SUM(CASE WHEN g.title_canon IS NULL       THEN 1 ELSE 0 END)       AS unmatched_games
FROM vgsales v
LEFT JOIN games g
    ON LOWER(TRIM(v.name_canon)) = LOWER(TRIM(g.title_canon));

-- ============================================================
-- STEP 6 : ANALYSIS QUERIES
-- ============================================================

-- ── 1. Overall sales summary ──────────────────────────────
SELECT
    COUNT(*)                        AS total_games,
    ROUND(SUM(global_sales), 2)     AS total_global_sales_millions,
    ROUND(AVG(global_sales), 2)     AS avg_sales_per_game,
    ROUND(MAX(global_sales), 2)     AS highest_single_game_sales
FROM vgsales;
 
-- 2. Sales by region
SELECT
    ROUND(SUM(na_sales), 2)      AS north_america,
    ROUND(SUM(eu_sales), 2)      AS europe,
    ROUND(SUM(jp_sales), 2)      AS japan,
    ROUND(SUM(other_sales), 2)   AS other_regions,
    ROUND(SUM(global_sales), 2)  AS total_global
FROM vgsales;
 
-- 3. Best selling platform
SELECT
    platform,
    COUNT(*)                        AS total_games,
    ROUND(SUM(global_sales), 2)     AS total_sales
FROM vgsales
GROUP BY platform
ORDER BY total_sales DESC
LIMIT 10;
 
-- 4. Top 10 best selling games
SELECT
    name, platform, publisher,
    ROUND(global_sales, 2) AS global_sales
FROM vgsales
ORDER BY global_sales DESC
LIMIT 10;
 
-- 5. Top publishers by global sales
SELECT
    publisher,
    COUNT(*)                        AS games_published,
    ROUND(SUM(global_sales), 2)     AS total_sales,
    ROUND(AVG(global_sales), 2)     AS avg_sales
FROM vgsales
WHERE publisher != 'Unknown'
GROUP BY publisher
ORDER BY total_sales DESC
LIMIT 10;
 
-- 6. Genre performance by sales
SELECT
    genre,
    COUNT(*)                        AS total_games,
    ROUND(SUM(global_sales), 2)     AS total_sales,
    ROUND(AVG(global_sales), 2)     AS avg_sales
FROM vgsales
GROUP BY genre
ORDER BY total_sales DESC;
 
-- 7. Game releases trend by year
SELECT
    year,
    COUNT(*)                        AS games_released,
    ROUND(SUM(global_sales), 2)     AS total_sales
FROM vgsales
WHERE year IS NOT NULL
GROUP BY year
ORDER BY year;
 
-- 8. Average rating by primary genre
SELECT
    primary_genre,
    COUNT(*)                        AS total_games,
    ROUND(AVG(rating), 2)           AS avg_rating,
    ROUND(AVG(plays), 2)            AS avg_plays
FROM games
WHERE primary_genre != 'Unknown'
GROUP BY primary_genre
ORDER BY avg_rating DESC
LIMIT 10;
 
-- 9. Top 10 highest rated games
SELECT
    title, team, rating,
    release_year, primary_genre,
    ROUND(plays, 2) AS plays
FROM games
WHERE rating IS NOT NULL
ORDER BY rating DESC
LIMIT 10;
 
-- 10. JOIN: Sales + Engagement combined
SELECT
    v.name,
    v.platform,
    v.genre,
    v.publisher,
    v.year,
    ROUND(v.global_sales, 2)   AS global_sales,
    g.rating,
    g.primary_genre,
    ROUND(g.plays, 2)          AS plays,
    ROUND(g.backlogs, 2)       AS backlogs,
    ROUND(g.wishlist, 2)       AS wishlist,
    CASE
        WHEN g.rating >= 4.0 THEN 'High Rated'
        WHEN g.rating >= 3.0 THEN 'Average Rated'
        WHEN g.rating IS NOT NULL THEN 'Low Rated'
        ELSE 'Not Rated'
    END AS rating_category
FROM vgsales v
LEFT JOIN games g ON v.name_canon = g.title_canon
WHERE g.rating IS NOT NULL
ORDER BY v.global_sales DESC
LIMIT 20;
 
-- 11. Platforms with most high rated games
SELECT
    v.platform,
    COUNT(*)                        AS high_rated_games,
    ROUND(AVG(g.rating), 2)         AS avg_rating,
    ROUND(SUM(v.global_sales), 2)   AS total_sales
FROM vgsales v
JOIN games g ON v.name_canon = g.title_canon
WHERE g.rating >= 4.0
GROUP BY v.platform
ORDER BY high_rated_games DESC
LIMIT 10;
 
-- 12. Year over year sales growth
WITH yearly AS (
    SELECT
        year,
        ROUND(SUM(global_sales), 2) AS total_sales
    FROM vgsales
    WHERE year IS NOT NULL
    GROUP BY year
)
SELECT
    year,
    total_sales,
    LAG(total_sales) OVER (ORDER BY year)                                AS prev_year_sales,
    ROUND(total_sales - LAG(total_sales) OVER (ORDER BY year), 2)        AS yoy_change
FROM yearly
ORDER BY year;
 
-- 13. Top selling game per platform
WITH ranked AS (
    SELECT
        name, platform, publisher,
        ROUND(global_sales, 2) AS global_sales,
        ROW_NUMBER() OVER (PARTITION BY platform ORDER BY global_sales DESC) AS rn
    FROM vgsales
)
SELECT name, platform, publisher, global_sales
FROM ranked
WHERE rn = 1
ORDER BY global_sales DESC;

-- ── 14. Rating category vs sales performance ──────────────
SELECT
    CASE
        WHEN g.rating >= 4.0 THEN 'High Rated (4.0+)'
        WHEN g.rating >= 3.0 THEN 'Average Rated (3.0-3.9)'
        ELSE                      'Low Rated (Below 3.0)'
    END                             AS rating_category,
    COUNT(*)                        AS total_games,
    ROUND(AVG(v.global_sales), 2)   AS avg_global_sales,
    ROUND(SUM(v.global_sales), 2)   AS total_global_sales
FROM vgsales v
JOIN games g
    ON LOWER(TRIM(v.name_canon)) = LOWER(TRIM(g.title_canon))
WHERE g.rating IS NOT NULL
GROUP BY rating_category
ORDER BY avg_global_sales DESC;

-- ── 15. Most wishlisted games with low plays (hidden gems) ─
SELECT
    title, rating, primary_genre,
    ROUND(CAST(plays    AS DECIMAL(10,2)), 2) AS plays,
    ROUND(CAST(wishlist AS DECIMAL(10,2)), 2) AS wishlist,
    release_year
FROM games
WHERE CAST(wishlist AS DECIMAL(10,2)) > 300
  AND CAST(plays    AS DECIMAL(10,2)) < 300
ORDER BY CAST(wishlist AS DECIMAL(10,2)) DESC
LIMIT 10;

-- ============================================================
-- STEP 7 : CREATE VIEW FOR POWER BI
-- ============================================================

CREATE OR REPLACE VIEW vw_game_summary AS
SELECT
    v.name,
    v.platform,
    v.genre                                           AS sales_genre,
    v.publisher,
    v.year,
    ROUND(v.na_sales,    2)                           AS na_sales,
    ROUND(v.eu_sales,    2)                           AS eu_sales,
    ROUND(v.jp_sales,    2)                           AS jp_sales,
    ROUND(v.other_sales, 2)                           AS other_sales,
    ROUND(v.global_sales,2)                           AS global_sales,
    g.rating,
    g.primary_genre,
    g.genres,
    ROUND(CAST(g.plays    AS DECIMAL(10,2)), 2)       AS plays,
    ROUND(CAST(g.backlogs AS DECIMAL(10,2)), 2)       AS backlogs,
    ROUND(CAST(g.wishlist AS DECIMAL(10,2)), 2)       AS wishlist,
    g.release_year,
    CASE
        WHEN g.rating >= 4.0 THEN 'High Rated'
        WHEN g.rating >= 3.0 THEN 'Average Rated'
        WHEN g.rating IS NOT NULL THEN 'Low Rated'
        ELSE 'Not Rated'
    END AS rating_category
FROM vgsales v
LEFT JOIN games g
    ON LOWER(TRIM(v.name_canon)) = LOWER(TRIM(g.title_canon));

-- Verify
SELECT 
    COUNT(*)                                            AS total_rows,
    SUM(CASE WHEN rating IS NOT NULL THEN 1 ELSE 0 END) AS matched,
    SUM(CASE WHEN rating IS NULL     THEN 1 ELSE 0 END) AS unmatched
FROM vw_game_summary;













 
