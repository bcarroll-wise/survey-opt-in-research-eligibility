-- =============================================================================
-- Research-email eligibility erosion from 30-day comms frequency capping
-- -----------------------------------------------------------------------------
-- Cohort: users opted IN to research email (SURVEYS.EMAIL = TRUE) in 6 markets.
-- For each of the last 90 days, what share of that fixed cohort would be
-- INELIGIBLE for a research email because they were contacted in the prior 30d?
--   Line 1 (pct_ineligible_any_email):  received ANY email comm in [D-30, D-1]
--   Line 2 (pct_ineligible_research):   received a RESEARCH email in [D-30, D-1]
-- Line 2 is a subset of Line 1, so the gap = ineligibility driven by non-research
-- comms. Denominator is the fixed cohort size (constant across all days).
--
-- Tunables: WINDOW_DAYS (lookback), spine length (90), cohort sample size (100k).
-- =============================================================================
WITH params AS (
    SELECT DATEADD('day', -90, CURRENT_DATE) AS start_date,
        CURRENT_DATE AS end_date,
        30 AS window_days
),
country_users AS (
    SELECT USER_ID,
        ADDRESS AS country
    FROM REPORTS.LOOKUP_USER_COUNTRY_AFFILIATION
    WHERE ADDRESS IN ('gbr', 'usa', 'aus', 'fra', 'deu', 'can')
),
-- Pool: everyone opted in to research email in those markets
opted_in_pool AS (
    SELECT n.USER_ID,
        g.country
    FROM NOTIFICATIONS.USER_PREFERENCES n
        INNER JOIN country_users g ON n.USER_ID = g.USER_ID
    WHERE n._SDC_DELETED_AT IS NULL
        AND n.CHANNELS_PREFERENCES :SURVEYS :EMAIL::BOOLEAN = TRUE
),
-- Deterministic 500k sample so the range-join below stays cheap (tune the LIMIT)
cohort AS (
    SELECT USER_ID,
        country
    FROM opted_in_pool
    ORDER BY HASH(USER_ID)
    LIMIT 500000
), cohort_size AS (
    SELECT COUNT(*) AS n
    FROM cohort
),
-- Daily x-axis: 91 points covering start_date .. end_date
date_spine AS (
    SELECT day
    FROM (
            SELECT DATEADD(
                    'day',
                    SEQ4(),
                    (
                        SELECT start_date
                        FROM params
                    )
                ) AS day
            FROM TABLE(GENERATOR(ROWCOUNT => 91))
        )
    WHERE day <= (
            SELECT end_date
            FROM params
        )
),
-- Email receipts for the cohort, one row per user x day, flagged research-or-not.
-- Pull from (start_date - window) so the earliest spine day has full lookback.
comms AS (
    SELECT c.USER_ID,
        CAST(c.LAST_RECEIVED_TIMESTAMP AS DATE) AS receipt_date,
        MAX(
            CASE
                WHEN c.PARENT_TAGS ILIKE '%Campaign Type/Research%' THEN 1
                ELSE 0
            END
        ) AS is_research
    FROM RPT_CRM.INT_COMMS_TRUNCATED c
        INNER JOIN cohort ch ON c.USER_ID = ch.USER_ID
    WHERE c.CHANNELS ILIKE '%email%'
        AND CAST(c.LAST_RECEIVED_TIMESTAMP AS DATE) >= DATEADD(
            'day',
            -(
                SELECT window_days
                FROM params
            ),
            (
                SELECT start_date
                FROM params
            )
        )
        AND CAST(c.LAST_RECEIVED_TIMESTAMP AS DATE) <= (
            SELECT end_date
            FROM params
        )
    GROUP BY 1,
        2
),
-- For each day, count distinct cohort users with a qualifying receipt in [D-window, D-1]
daily AS (
    SELECT d.day,
        COUNT(DISTINCT c.USER_ID) AS users_blocked_any_email,
        COUNT(
            DISTINCT CASE
                WHEN c.is_research = 1 THEN c.USER_ID
            END
        ) AS users_blocked_research
    FROM date_spine d
        INNER JOIN comms c ON c.receipt_date BETWEEN DATEADD(
            'day',
            -(
                SELECT window_days
                FROM params
            ),
            d.day
        )
        AND DATEADD('day', -1, d.day)
    GROUP BY d.day
)
SELECT d.day,
    cs.n AS cohort_users,
    d.users_blocked_any_email,
    d.users_blocked_research,
    100.0 * d.users_blocked_any_email / cs.n AS pct_ineligible_any_email,
    100.0 * d.users_blocked_research / cs.n AS pct_ineligible_research
FROM daily d
    CROSS JOIN cohort_size cs
ORDER BY d.day;