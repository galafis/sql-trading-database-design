-- ============================================================================
-- Analytical Queries - Top Performers
-- Author: Gabriel Demetrios Lafis
-- Description: Queries to analyze top performing accounts and instruments
-- ============================================================================

-- ============================================================================
-- Query: Top 10 Accounts by P&L
-- ============================================================================
SELECT 
    a.account_id,
    a.account_number,
    a.account_type,
    a.balance,
    pm.total_pnl,
    pm.win_rate,
    pm.profit_factor,
    pm.total_trades,
    pm.winning_trades,
    pm.losing_trades
FROM accounts a
JOIN v_performance_metrics pm ON a.account_id = pm.account_id
WHERE a.is_active = true
ORDER BY pm.total_pnl DESC
LIMIT 10;

-- ============================================================================
-- Query: Top 10 Most Traded Instruments
-- ============================================================================
SELECT 
    i.symbol,
    i.instrument_name,
    i.instrument_type,
    ip.total_trades,
    ip.total_volume,
    ip.total_value,
    ip.unique_traders,
    ip.last_trade_at
FROM v_instrument_performance ip
JOIN instruments i ON ip.instrument_id = i.instrument_id
ORDER BY ip.total_trades DESC
LIMIT 10;

-- ============================================================================
-- Query: Top Instruments by Profitability
-- ============================================================================
SELECT 
    symbol,
    instrument_name,
    instrument_type,
    closed_positions,
    total_realized_pnl,
    avg_realized_pnl,
    win_rate,
    gross_profit,
    gross_loss,
    best_trade,
    worst_trade
FROM v_instrument_pnl
WHERE closed_positions > 0
ORDER BY total_realized_pnl DESC
LIMIT 10;

-- ============================================================================
-- Query: Account Performance Over Time
-- ============================================================================
SELECT 
    account_id,
    account_number,
    month,
    total_trades,
    monthly_pnl,
    monthly_return_pct,
    profit_factor,
    total_commission,
    SUM(monthly_pnl) OVER (PARTITION BY account_id ORDER BY month) AS cumulative_pnl
FROM v_monthly_pnl_summary
WHERE account_id = 1  -- Replace with specific account ID
ORDER BY month DESC
LIMIT 12;

-- ============================================================================
-- Query: Trading Pattern Analysis
-- ============================================================================
SELECT 
    EXTRACT(DOW FROM executed_at) AS day_of_week,
    CASE 
        WHEN EXTRACT(DOW FROM executed_at) = 0 THEN 'Sunday'
        WHEN EXTRACT(DOW FROM executed_at) = 1 THEN 'Monday'
        WHEN EXTRACT(DOW FROM executed_at) = 2 THEN 'Tuesday'
        WHEN EXTRACT(DOW FROM executed_at) = 3 THEN 'Wednesday'
        WHEN EXTRACT(DOW FROM executed_at) = 4 THEN 'Thursday'
        WHEN EXTRACT(DOW FROM executed_at) = 5 THEN 'Friday'
        WHEN EXTRACT(DOW FROM executed_at) = 6 THEN 'Saturday'
    END AS day_name,
    COUNT(*) AS total_trades,
    AVG(value) AS avg_trade_value,
    SUM(value) AS total_volume,
    COUNT(DISTINCT account_id) AS unique_accounts
FROM trades
GROUP BY EXTRACT(DOW FROM executed_at)
ORDER BY day_of_week;

-- ============================================================================
-- Query: Hourly Trading Activity
-- ============================================================================
SELECT 
    EXTRACT(HOUR FROM executed_at) AS hour_of_day,
    COUNT(*) AS trade_count,
    SUM(value) AS total_volume,
    AVG(value) AS avg_trade_value,
    COUNT(DISTINCT account_id) AS unique_accounts,
    COUNT(DISTINCT instrument_id) AS unique_instruments
FROM trades
WHERE executed_at >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY EXTRACT(HOUR FROM executed_at)
ORDER BY hour_of_day;

-- ============================================================================
-- Query: Position Concentration Risk
-- ============================================================================
SELECT 
    a.account_id,
    a.account_number,
    a.balance,
    COUNT(p.position_id) AS total_positions,
    MAX(p.quantity * p.current_price) AS largest_position,
    SUM(p.quantity * p.current_price) AS total_exposure,
    (MAX(p.quantity * p.current_price) / NULLIF(SUM(p.quantity * p.current_price), 0)) * 100 AS concentration_pct,
    (SUM(p.quantity * p.current_price) / NULLIF(a.balance, 0)) * 100 AS exposure_pct
FROM accounts a
JOIN positions p ON a.account_id = p.account_id
WHERE a.is_active = true
GROUP BY a.account_id, a.account_number, a.balance
HAVING (MAX(p.quantity * p.current_price) / NULLIF(SUM(p.quantity * p.current_price), 0)) * 100 > 25
ORDER BY concentration_pct DESC;

-- ============================================================================
-- Query: Win/Loss Streak Analysis
-- ============================================================================
WITH pnl_sequence AS (
    SELECT 
        account_id,
        position_id,
        realized_pnl,
        CASE WHEN realized_pnl > 0 THEN 1 ELSE -1 END AS win_loss,
        LAG(CASE WHEN realized_pnl > 0 THEN 1 ELSE -1 END) OVER (
            PARTITION BY account_id ORDER BY closed_at
        ) AS prev_win_loss,
        closed_at
    FROM position_history
),
streaks AS (
    SELECT 
        account_id,
        win_loss,
        COUNT(*) AS streak_length,
        SUM(realized_pnl) AS streak_pnl
    FROM (
        SELECT 
            account_id,
            position_id,
            realized_pnl,
            win_loss,
            SUM(CASE WHEN win_loss != COALESCE(prev_win_loss, win_loss) THEN 1 ELSE 0 END) 
                OVER (PARTITION BY account_id ORDER BY closed_at) AS streak_id
        FROM pnl_sequence
    ) s
    GROUP BY account_id, win_loss, streak_id
)
SELECT 
    account_id,
    CASE WHEN win_loss = 1 THEN 'Winning' ELSE 'Losing' END AS streak_type,
    MAX(streak_length) AS max_streak,
    AVG(streak_length) AS avg_streak,
    MAX(streak_pnl) AS best_streak_pnl,
    MIN(streak_pnl) AS worst_streak_pnl
FROM streaks
GROUP BY account_id, win_loss
ORDER BY account_id, win_loss DESC;
