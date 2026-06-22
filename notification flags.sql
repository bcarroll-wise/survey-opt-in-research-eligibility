-- =============================================================================
-- Notification Preferences: Raw flags per user (500K random sample)
-- Source: NOTIFICATIONS.USER_PREFERENCES (source-of-truth for current state)
-- Enriched with: profile type + device platform
-- =============================================================================
-- Mobile App Mapping:
--   "Your transfers and balances"     → TRANSFERS (email, push) + BALANCES_AND_CARDS (email, push)
--   "Your debit card"                 → BALANCES_AND_CARDS (email, push)
--   "Personalised updates"            → PROMOTIONAL (email, push)
--   "Invitations to share feedback"   → SURVEYS (email only)
--   "Update on causes we care about"  → CAMPAIGNS (email only)
-- =============================================================================

WITH country_users AS (
    SELECT USER_ID, ADDRESS AS country
    FROM REPORTS.LOOKUP_USER_COUNTRY_AFFILIATION
    WHERE ADDRESS IN ('gbr', 'usa', 'aus', 'fra', 'deu', 'can')
),

sample_users AS (
    SELECT
        n.USER_ID,
        g.country,
        CHANNELS_PREFERENCES:TRANSFERS:EMAIL::BOOLEAN           AS transfers_email,
        CHANNELS_PREFERENCES:TRANSFERS:PUSH::BOOLEAN            AS transfers_push,
        CHANNELS_PREFERENCES:BALANCES_AND_CARDS:EMAIL::BOOLEAN  AS balances_cards_email,
        CHANNELS_PREFERENCES:BALANCES_AND_CARDS:PUSH::BOOLEAN   AS balances_cards_push,
        CHANNELS_PREFERENCES:PROMOTIONAL:EMAIL::BOOLEAN         AS promotional_email,
        CHANNELS_PREFERENCES:PROMOTIONAL:PUSH::BOOLEAN          AS promotional_push,
        CHANNELS_PREFERENCES:SURVEYS:EMAIL::BOOLEAN             AS surveys_email,
        CHANNELS_PREFERENCES:CAMPAIGNS:EMAIL::BOOLEAN           AS campaigns_email
    FROM NOTIFICATIONS.USER_PREFERENCES n
    INNER JOIN country_users g ON n.USER_ID = g.USER_ID
    WHERE n._SDC_DELETED_AT IS NULL
),

-- Business vs Personal profile
profiles AS (
    SELECT
        USER_ID,
        CASE
            WHEN CLASS = 'com.transferwise.fx.user.BusinessUserProfile' THEN 'BUSINESS'
            ELSE 'PERSONAL'
        END AS profile_type
    FROM PROFILE.USER_PROFILE
),

-- Most recently registered active device per user (IOS / ANDROID)
devices AS (
    SELECT
        USER_ID,
        CHANNEL AS device_platform,
        ROW_NUMBER() OVER (PARTITION BY USER_ID ORDER BY DATE_REGISTERED DESC) AS rn
    FROM NOTIFICATIONS.DEVICES
    WHERE CHANNEL IN ('IOS', 'ANDROID')
      AND DATE_DELETED IS NULL
)

SELECT
    s.USER_ID,
    s.country,
    p.profile_type,
    d.device_platform,
    s.transfers_email,
    s.transfers_push,
    s.balances_cards_email,
    s.balances_cards_push,
    s.promotional_email,
    s.promotional_push,
    s.surveys_email,
    s.campaigns_email
FROM sample_users s
LEFT JOIN profiles p ON s.USER_ID = p.USER_ID
LEFT JOIN devices d ON s.USER_ID = d.USER_ID AND d.rn = 1
LIMIT 500000;
