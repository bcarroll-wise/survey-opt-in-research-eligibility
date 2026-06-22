-- =============================================================================
-- Compare NOTIFICATIONS.USER_PREFERENCES (source of truth) vs RPT_CRM tables
-- Goal: Identify disparity between what users set in-app and what CRM reports
-- =============================================================================
WITH country_users AS (
    SELECT USER_ID,
        ADDRESS AS country
    FROM REPORTS.LOOKUP_USER_COUNTRY_AFFILIATION
    WHERE ADDRESS IN ('gbr', 'usa', 'aus', 'fra', 'deu', 'can')
),
sample_users AS (
    SELECT n.USER_ID,
        g.country,
        CHANNELS_PREFERENCES :TRANSFERS :EMAIL::BOOLEAN AS transfers_email,
        CHANNELS_PREFERENCES :TRANSFERS :PUSH::BOOLEAN AS transfers_push,
        CHANNELS_PREFERENCES :BALANCES_AND_CARDS :EMAIL::BOOLEAN AS balances_cards_email,
        CHANNELS_PREFERENCES :BALANCES_AND_CARDS :PUSH::BOOLEAN AS balances_cards_push,
        CHANNELS_PREFERENCES :PROMOTIONAL :EMAIL::BOOLEAN AS promotional_email,
        CHANNELS_PREFERENCES :PROMOTIONAL :PUSH::BOOLEAN AS promotional_push,
        CHANNELS_PREFERENCES :SURVEYS :EMAIL::BOOLEAN AS surveys_email,
        CHANNELS_PREFERENCES :CAMPAIGNS :EMAIL::BOOLEAN AS campaigns_email
    FROM NOTIFICATIONS.USER_PREFERENCES n
        INNER JOIN country_users g ON n.USER_ID = g.USER_ID
    WHERE n._SDC_DELETED_AT IS NULL
),
profiles AS (
    SELECT USER_ID,
        CASE
            WHEN CLASS = 'com.transferwise.fx.user.BusinessUserProfile' THEN 'BUSINESS'
            ELSE 'PERSONAL'
        END AS profile_type
    FROM PROFILE.USER_PROFILE
),
devices AS (
    SELECT USER_ID,
        CHANNEL AS device_platform,
        ROW_NUMBER() OVER (
            PARTITION BY USER_ID
            ORDER BY DATE_REGISTERED DESC
        ) AS rn
    FROM NOTIFICATIONS.DEVICES
    WHERE CHANNEL IN ('IOS', 'ANDROID')
        AND DATE_DELETED IS NULL
),
-- Latest row per user from CRM preferences log (avoid fan-out)
crm_latest AS (
    SELECT USER_ID,
        CHANNELS_PREFERENCES,
        DATE_UPDATED,
        ROW_NUMBER() OVER (
            PARTITION BY USER_ID
            ORDER BY DATE_UPDATED DESC
        ) AS rn
    FROM RPT_CRM.USER_CHANNELS_PREFERENCES_LOG
)
SELECT s.USER_ID,
    s.country,
    p.profile_type,
    d.device_platform,
    elig.ASSIGNED_GLOBAL_GROUP,
    s.transfers_email,
    s.transfers_push,
    s.balances_cards_email,
    s.balances_cards_push,
    s.promotional_email,
    s.promotional_push,
    s.surveys_email,
    s.campaigns_email,
    opt_out.DATE_UPDATED AS survey_opt_out_from_INT_NOTIFICATION_OPT_OUTS,
    crm_log.CHANNELS_PREFERENCES AS CRM_LOGGED_PREFS,
    CASE
        WHEN promo.USER_ID IS NOT NULL THEN 1
        ELSE 0
    END AS OPTED_IN_TO_PROMO_EMAIL
FROM sample_users s
    LEFT JOIN profiles p ON s.USER_ID = p.USER_ID
    LEFT JOIN devices d ON s.USER_ID = d.USER_ID
    AND d.rn = 1
    LEFT JOIN RPT_CRM.INT_ALL_ELIGIBLE_USERS_GLOBAL_GROUP_ASSIGNMENT elig ON s.USER_ID = elig.USER_ID
    LEFT JOIN RPT_CRM.INT_NOTIFICATION_OPT_OUTS opt_out ON s.USER_ID = opt_out.USER_ID
    AND opt_out.PREFERENCE_NAME = 'SURVEYS.EMAIL'
    LEFT JOIN crm_latest crm_log ON s.USER_ID = crm_log.USER_ID
    AND crm_log.rn = 1
    LEFT JOIN RPT_CRM.INT_PROMO_EMAIL_OPT_INS promo ON s.USER_ID = promo.USER_ID
LIMIT 1000000;