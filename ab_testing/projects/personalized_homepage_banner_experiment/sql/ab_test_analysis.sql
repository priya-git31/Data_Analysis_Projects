
-- A/B Testing Project: Personalized Homepage Banner
-- Experiment: EXP_2024_Q2_HP_BANNER
-- Goal: Measure whether a personalized homepage banner improves engagement and purchase behavior.

-- 1) Experiment population
WITH experiment_population AS (
    SELECT
        u.user_id,
        u.segment,
        u.favorite_genre,
        u.device,
        u.region,
        u.clv_score,
        a.variant,
        a.entry_date
    FROM users u
    INNER JOIN experiment_assignment a
        ON u.user_id = a.user_id
    WHERE a.experiment_id = 'EXP_2024_Q2_HP_BANNER'
),

-- 2) User-level event flags
click_flags AS (
    SELECT
        user_id,
        1 AS clicked_banner
    FROM page_events
    WHERE event_type = 'banner_click'
    GROUP BY 1
),

add_to_cart_flags AS (
    SELECT
        user_id,
        1 AS added_to_cart
    FROM page_events
    WHERE event_type = 'add_to_cart'
    GROUP BY 1
),

purchase_flags AS (
    SELECT
        user_id,
        COUNT(DISTINCT order_id) AS orders,
        SUM(order_value) AS revenue,
        SUM(units) AS total_units,
        1 AS purchased
    FROM orders
    GROUP BY 1
),

-- 3) Final user-level table
ab_user_level AS (
    SELECT
        p.*,
        COALESCE(c.clicked_banner, 0) AS clicked_banner,
        COALESCE(atc.added_to_cart, 0) AS added_to_cart,
        COALESCE(pr.purchased, 0) AS purchased,
        COALESCE(pr.orders, 0) AS orders,
        COALESCE(pr.revenue, 0) AS revenue,
        COALESCE(pr.total_units, 0) AS total_units
    FROM experiment_population p
    LEFT JOIN click_flags c
        ON p.user_id = c.user_id
    LEFT JOIN add_to_cart_flags atc
        ON p.user_id = atc.user_id
    LEFT JOIN purchase_flags pr
        ON p.user_id = pr.user_id
)

-- 4) Overall experiment summary
SELECT
    variant,
    COUNT(DISTINCT user_id) AS users,
    SUM(clicked_banner) AS clicks,
    SUM(added_to_cart) AS add_to_carts,
    SUM(purchased) AS purchasers,
    ROUND(SUM(clicked_banner) * 1.0 / COUNT(DISTINCT user_id), 4) AS ctr,
    ROUND(SUM(added_to_cart) * 1.0 / COUNT(DISTINCT user_id), 4) AS add_to_cart_rate,
    ROUND(SUM(purchased) * 1.0 / COUNT(DISTINCT user_id), 4) AS conversion_rate,
    ROUND(SUM(revenue) * 1.0 / COUNT(DISTINCT user_id), 4) AS revenue_per_visitor
FROM ab_user_level
GROUP BY 1
ORDER BY 1;

-- 5) Segment-level performance
SELECT
    segment,
    variant,
    COUNT(DISTINCT user_id) AS users,
    ROUND(SUM(clicked_banner) * 1.0 / COUNT(DISTINCT user_id), 4) AS ctr,
    ROUND(SUM(added_to_cart) * 1.0 / COUNT(DISTINCT user_id), 4) AS add_to_cart_rate,
    ROUND(SUM(purchased) * 1.0 / COUNT(DISTINCT user_id), 4) AS conversion_rate
FROM ab_user_level
GROUP BY 1, 2
ORDER BY 1, 2;

-- 6) Daily cohort trend using window functions
WITH daily AS (
    SELECT
        entry_date,
        variant,
        COUNT(DISTINCT user_id) AS users,
        SUM(purchased) AS purchasers
    FROM ab_user_level
    GROUP BY 1, 2
)
SELECT
    entry_date,
    variant,
    users,
    purchasers,
    ROUND(purchasers * 1.0 / users, 4) AS conversion_rate,
    ROUND(AVG(purchasers * 1.0 / users) OVER (
        PARTITION BY variant
        ORDER BY entry_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 4) AS rolling_7d_conversion_rate
FROM daily
ORDER BY entry_date, variant;

-- 7) Device performance
SELECT
    device,
    variant,
    COUNT(DISTINCT user_id) AS users,
    ROUND(SUM(clicked_banner) * 1.0 / COUNT(DISTINCT user_id), 4) AS ctr,
    ROUND(SUM(purchased) * 1.0 / COUNT(DISTINCT user_id), 4) AS conversion_rate
FROM ab_user_level
GROUP BY 1, 2
ORDER BY 1, 2;
