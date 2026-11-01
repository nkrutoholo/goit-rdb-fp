-- Фінальний проєкт GoIT «Реляційні бази даних»: увесь SQL у порядку notebook RDB_FINAL_PROJECT.ipynb.
-- Запуск з кореня репозиторію: psql -v ON_ERROR_STOP=1 -d <база> -f final_project.sql

-- ========================================================================
-- Завдання 1. Завантаження даних
-- ========================================================================

-- 1.2. Схема `pandemic`

CREATE SCHEMA IF NOT EXISTS pandemic;
SET search_path TO pandemic;

SELECT current_schema() AS current_schema,
       current_setting('search_path') AS search_path;

-- 1.3. Таблиця `infectious_cases` та імпорт через COPY

DROP TABLE IF EXISTS infectious_cases;

-- Сирий імпорт CSV: 12 колонок у порядку файлу, усі TEXT
CREATE TABLE infectious_cases (
    entity               TEXT,
    code                 TEXT,
    year                 TEXT,
    number_yaws          TEXT,
    polio_cases          TEXT,
    cases_guinea_worm    TEXT,
    number_rabies        TEXT,
    number_malaria       TEXT,
    number_hiv           TEXT,
    number_tuberculosis  TEXT,
    number_smallpox      TEXT,
    number_cholera_cases TEXT
);

-- У notebook CSV вантажить COPY FROM STDIN через psycopg2; у psql те саме робить \copy
\copy pandemic.infectious_cases FROM 'data/infectious_cases.csv' WITH (FORMAT csv, HEADER true)

SELECT COUNT(*) AS loaded_rows
FROM infectious_cases;

-- 1.4. Огляд даних

SELECT *
FROM infectious_cases
ORDER BY entity, year
LIMIT 5;

SELECT COUNT(*)                                            AS n_rows,
       COUNT(DISTINCT entity)                              AS n_entities,
       (SELECT COUNT(*)
        FROM (SELECT DISTINCT entity, code FROM infectious_cases) AS pairs) AS n_entity_code_pairs,
       COUNT(DISTINCT entity) FILTER (WHERE code IS NULL)  AS n_entities_without_code,
       COUNT(*) FILTER (WHERE code IS NULL)                AS n_rows_without_code,
       MIN(year)                                           AS min_year,
       MAX(year)                                           AS max_year
FROM infectious_cases;

-- Чи однозначно code визначає entity і чи не повторюється пара (entity, year)
SELECT
    (SELECT COUNT(*)
     FROM (SELECT code FROM infectious_cases
           WHERE code IS NOT NULL
           GROUP BY code
           HAVING COUNT(DISTINCT entity) > 1) AS t) AS codes_with_several_entities,
    (SELECT COUNT(*)
     FROM (SELECT entity, year FROM infectious_cases
           GROUP BY entity, year
           HAVING COUNT(*) > 1) AS t)               AS duplicate_entity_year;

-- Entity без коду (регіони, групи країн) і службові коди OWID_*
SELECT entity, code, COUNT(*) AS n_rows
FROM infectious_cases
WHERE code IS NULL OR code LIKE 'OWID%'
GROUP BY entity, code
ORDER BY code NULLS FIRST, entity;

-- Профіль колонок з показниками: порожні поля, числа, інший текст
WITH v AS (
    SELECT c.ord, c.column_name, c.value
    FROM infectious_cases AS r
    CROSS JOIN LATERAL (VALUES
        (1, 'number_yaws',          r.number_yaws),
        (2, 'polio_cases',          r.polio_cases),
        (3, 'cases_guinea_worm',    r.cases_guinea_worm),
        (4, 'number_rabies',        r.number_rabies),
        (5, 'number_malaria',       r.number_malaria),
        (6, 'number_hiv',           r.number_hiv),
        (7, 'number_tuberculosis',  r.number_tuberculosis),
        (8, 'number_smallpox',      r.number_smallpox),
        (9, 'number_cholera_cases', r.number_cholera_cases)
    ) AS c(ord, column_name, value)
)
SELECT column_name,
       COUNT(*) FILTER (WHERE value IS NULL)                         AS n_empty,
       COUNT(*) FILTER (WHERE value ~ '^-?[0-9]+(\.[0-9]+)?$')       AS n_numeric,
       COUNT(*) FILTER (WHERE value ~ '^-?[0-9]+$')                  AS n_integer,
       COUNT(*) FILTER (WHERE value IS NOT NULL
                          AND value !~ '^-?[0-9]+(\.[0-9]+)?$')      AS n_other
FROM v
GROUP BY ord, column_name
ORDER BY ord;

-- ========================================================================
-- Завдання 2. Нормалізація до 3НФ
-- ========================================================================

DROP TABLE IF EXISTS infectious_cases_normalized, entities;

-- Довідник: одна entity = один рядок; entity і code однозначно визначають одне одного
CREATE TABLE entities (
    id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entity TEXT NOT NULL UNIQUE,
    code   TEXT UNIQUE  -- NULL у регіонів і груп без коду; UNIQUE допускає кілька NULL
);

-- Показники: один рядок = одна entity в один рік
CREATE TABLE infectious_cases_normalized (
    id                   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entity_id            INTEGER NOT NULL REFERENCES entities (id),
    year                 INTEGER NOT NULL,
    number_yaws          INTEGER,
    polio_cases          INTEGER,
    cases_guinea_worm    INTEGER,
    number_rabies        DOUBLE PRECISION,
    number_malaria       DOUBLE PRECISION,
    number_hiv           DOUBLE PRECISION,
    number_tuberculosis  DOUBLE PRECISION,
    number_smallpox      INTEGER,
    number_cholera_cases INTEGER,
    UNIQUE (entity_id, year)
);

INSERT INTO entities (entity, code)
SELECT DISTINCT entity, code
FROM infectious_cases
ORDER BY entity;

-- JOIN лише по entity: у 34 entity code = NULL, а NULL = NULL не дає TRUE
INSERT INTO infectious_cases_normalized (
    entity_id, year, number_yaws, polio_cases, cases_guinea_worm, number_rabies,
    number_malaria, number_hiv, number_tuberculosis, number_smallpox, number_cholera_cases
)
SELECT e.id,
       r.year::INTEGER,
       NULLIF(TRIM(r.number_yaws), '')::INTEGER,
       NULLIF(TRIM(r.polio_cases), '')::INTEGER,
       NULLIF(TRIM(r.cases_guinea_worm), '')::INTEGER,
       NULLIF(TRIM(r.number_rabies), '')::DOUBLE PRECISION,
       NULLIF(TRIM(r.number_malaria), '')::DOUBLE PRECISION,
       NULLIF(TRIM(r.number_hiv), '')::DOUBLE PRECISION,
       NULLIF(TRIM(r.number_tuberculosis), '')::DOUBLE PRECISION,
       NULLIF(TRIM(r.number_smallpox), '')::INTEGER,
       NULLIF(TRIM(r.number_cholera_cases), '')::INTEGER
FROM infectious_cases AS r
JOIN entities AS e ON e.entity = r.entity
ORDER BY e.id, r.year::INTEGER;

-- 2.1. Перевірка нормалізації

SELECT 'infectious_cases' AS table_name, COUNT(*) AS n_rows FROM infectious_cases
UNION ALL
SELECT 'entities', COUNT(*) FROM entities
UNION ALL
SELECT 'infectious_cases_normalized', COUNT(*) FROM infectious_cases_normalized;

SELECT *
FROM entities
ORDER BY id
LIMIT 5;

SELECT *
FROM infectious_cases_normalized
ORDER BY id
LIMIT 5;

-- Декомпозиція без втрат: збираємо рядки назад і порівнюємо з raw у тих самих типах
WITH rebuilt AS (
    SELECT e.entity, e.code, n.year,
           n.number_yaws, n.polio_cases, n.cases_guinea_worm, n.number_rabies,
           n.number_malaria, n.number_hiv, n.number_tuberculosis,
           n.number_smallpox, n.number_cholera_cases
    FROM infectious_cases_normalized AS n
    JOIN entities AS e ON e.id = n.entity_id
),
raw_typed AS (
    SELECT entity,
           code,
           year::INTEGER                                           AS year,
           NULLIF(TRIM(number_yaws), '')::INTEGER                  AS number_yaws,
           NULLIF(TRIM(polio_cases), '')::INTEGER                  AS polio_cases,
           NULLIF(TRIM(cases_guinea_worm), '')::INTEGER            AS cases_guinea_worm,
           NULLIF(TRIM(number_rabies), '')::DOUBLE PRECISION       AS number_rabies,
           NULLIF(TRIM(number_malaria), '')::DOUBLE PRECISION      AS number_malaria,
           NULLIF(TRIM(number_hiv), '')::DOUBLE PRECISION          AS number_hiv,
           NULLIF(TRIM(number_tuberculosis), '')::DOUBLE PRECISION AS number_tuberculosis,
           NULLIF(TRIM(number_smallpox), '')::INTEGER              AS number_smallpox,
           NULLIF(TRIM(number_cholera_cases), '')::INTEGER         AS number_cholera_cases
    FROM infectious_cases
)
SELECT 'raw без rebuilt' AS check_name, COUNT(*) AS n_rows
FROM (SELECT * FROM raw_typed EXCEPT ALL SELECT * FROM rebuilt) AS missing
UNION ALL
SELECT 'rebuilt без raw', COUNT(*)
FROM (SELECT * FROM rebuilt EXCEPT ALL SELECT * FROM raw_typed) AS extra;

-- ========================================================================
-- Завдання 3. Аналіз `number_rabies`
-- ========================================================================

SELECT e.id,
       e.entity,
       e.code,
       ROUND(AVG(n.number_rabies)::NUMERIC, 2) AS avg_rabies,
       ROUND(MIN(n.number_rabies)::NUMERIC, 2) AS min_rabies,
       ROUND(MAX(n.number_rabies)::NUMERIC, 2) AS max_rabies,
       ROUND(SUM(n.number_rabies)::NUMERIC, 2) AS sum_rabies
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
WHERE n.number_rabies IS NOT NULL
GROUP BY e.id, e.entity, e.code
ORDER BY AVG(n.number_rabies) DESC
LIMIT 10;

-- 3.1. Навіщо `WHERE number_rabies IS NOT NULL`

SELECT COUNT(*)                              AS n_entities,
       COUNT(*) FILTER (WHERE n_values = 0) AS n_without_rabies
FROM (SELECT e.id, COUNT(n.number_rabies) AS n_values
      FROM entities AS e
      LEFT JOIN infectious_cases_normalized AS n ON n.entity_id = e.id
      GROUP BY e.id) AS per_entity;

-- Той самий запит без WHERE: першими йдуть entity без даних
SELECT e.entity, e.code, AVG(n.number_rabies) AS avg_rabies
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
GROUP BY e.id, e.entity, e.code
ORDER BY AVG(n.number_rabies) DESC
LIMIT 3;

-- 3.2. Додатково: лише країни

SELECT e.id,
       e.entity,
       e.code,
       ROUND(AVG(n.number_rabies)::NUMERIC, 2) AS avg_rabies,
       ROUND(MIN(n.number_rabies)::NUMERIC, 2) AS min_rabies,
       ROUND(MAX(n.number_rabies)::NUMERIC, 2) AS max_rabies,
       ROUND(SUM(n.number_rabies)::NUMERIC, 2) AS sum_rabies
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
WHERE n.number_rabies IS NOT NULL
  AND e.code IS NOT NULL
  AND e.code NOT LIKE 'OWID%'
GROUP BY e.id, e.entity, e.code
ORDER BY AVG(n.number_rabies) DESC
LIMIT 10;

-- ========================================================================
-- Завдання 4. Різниця в роках
-- ========================================================================

SELECT e.entity,
       n.year,
       MAKE_DATE(n.year, 1, 1)                                                AS first_jan,
       CURRENT_DATE                                                           AS today,
       EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(n.year, 1, 1)))::INTEGER AS years_diff
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
WHERE e.entity = 'Ukraine'
  AND n.year IN (1980, 1991, 2000, 2010, 2022)
ORDER BY n.year;

-- Діапазон по всій таблиці
SELECT COUNT(*)  AS n_rows,
       MIN(year) AS min_year,
       MAX(year) AS max_year,
       MAX(EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(year, 1, 1)))::INTEGER) AS max_years_diff,
       MIN(EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(year, 1, 1)))::INTEGER) AS min_years_diff
FROM infectious_cases_normalized;

-- ========================================================================
-- Завдання 5. Власні функції
-- ========================================================================

-- 5.1. `years_since(year)`

CREATE OR REPLACE FUNCTION years_since(p_year INTEGER)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(p_year, 1, 1)))::INTEGER;
$$;

-- Приклад з умови: 1996 -> 1996-01-01 -> різниця в роках до сьогодні
SELECT 1996                   AS year,
       MAKE_DATE(1996, 1, 1)  AS first_jan,
       CURRENT_DATE           AS today,
       years_since(1996)      AS years_since;

SELECT e.entity, n.year, years_since(n.year) AS years_since
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
WHERE e.entity = 'Ukraine'
  AND n.year IN (1980, 1991, 2000, 2010, 2022)
ORDER BY n.year;

-- Звірка функції з вбудованим виразом із завдання 4 по всіх рядках
SELECT COUNT(*) AS n_rows,
       COUNT(*) FILTER (
           WHERE years_since(year)
                 <> EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(year, 1, 1)))::INTEGER
       ) AS n_mismatches
FROM infectious_cases_normalized;

-- 5.2. `avg_cases_per_period(cases_per_year, divisor)`

CREATE OR REPLACE FUNCTION avg_cases_per_period(
    p_cases_per_year DOUBLE PRECISION,
    p_divisor        DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_cases_per_year / NULLIF(p_divisor, 0);
$$;

-- Перевірка на простих числах: 1200 випадків на рік
SELECT avg_cases_per_period(1200, 12) AS per_month,
       avg_cases_per_period(1200, 4)  AS per_quarter,
       avg_cases_per_period(1200, 2)  AS per_half_year,
       avg_cases_per_period(1200, 0)  AS divisor_zero;

SELECT e.entity,
       n.year,
       ROUND(n.number_rabies::NUMERIC, 2)                           AS rabies_per_year,
       ROUND(avg_cases_per_period(n.number_rabies, 12)::NUMERIC, 2) AS per_month,
       ROUND(avg_cases_per_period(n.number_rabies, 4)::NUMERIC, 2)  AS per_quarter,
       ROUND(avg_cases_per_period(n.number_rabies, 2)::NUMERIC, 2)  AS per_half_year
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
WHERE n.number_rabies IS NOT NULL
  AND e.entity = 'India'
ORDER BY n.year DESC
LIMIT 10;

-- Скільки записів підходять під фільтр і чи сходиться функція з діленням
SELECT COUNT(*) AS n_numeric_rows,
       COUNT(*) FILTER (WHERE avg_cases_per_period(number_rabies, 12) <> number_rabies / 12) AS n_mismatches_month,
       COUNT(*) FILTER (WHERE avg_cases_per_period(number_rabies, 4)  <> number_rabies / 4)  AS n_mismatches_quarter,
       COUNT(*) FILTER (WHERE avg_cases_per_period(number_rabies, 2)  <> number_rabies / 2)  AS n_mismatches_half_year
FROM infectious_cases_normalized
WHERE number_rabies IS NOT NULL;
