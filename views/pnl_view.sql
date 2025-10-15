-- ============================================================================
-- P&L Reporting Views
-- Author: Gabriel Demetrios Lafis
-- Description: Views for profit and loss reporting and analysis
-- ============================================================================

-- ============================================================================
-- View: Daily P&L Summary
-- ============================================================================
CREATE OR REPLACE VIEW v_daily_pnl_summary AS
SELECT 
    a.account_id,
    a.account_number,
    DATE_TRUNC('day', t.executed_at)::DATE AS trade_date,
    
    -- Trade counts
    COUNT(t.trade_id) AS total_trades,
    COUNT(CASE WHEN t.side = 'buy' THEN 1 END) AS buy_trades,
    COUNT(CASE WHEN t.side = 'sell' THEN 1 END) AS sell_trades,
    
    -- Volume
    SUM(t.quantity) AS total_quantity,
    SUM(t.value) AS total_value,
    
    -- Costs
    SUM(t.commission) AS total_commission,
    
    -- P&L calculation
    SUM(CASE 
        WHEN t.side = 'sell' THEN t.value - t.commission
        ELSE -(t.value + t.commission)
    END) AS daily_pnl,
    
    -- Profit and loss breakdown
    SUM(CASE 
        WHEN t.side = 'sell' AND (t.value - t.commission) > 0 THEN t.value - t.commission
        ELSE 0
    END) AS gross_profit,
    
    SUM(CASE 
        WHEN t.side = 'buy' OR (t.side = 'sell' AND (t.value - t.commission) < 0)
        THEN ABS(t.value + t.commission)
        ELSE 0
    END) AS gross_loss,
    
    -- Returns
    CASE 
        WHEN a.balance > 0 THEN
            (SUM(CASE 
                WHEN t.side = 'sell' THEN t.value - t.commission
                ELSE -(t.value + t.commission)
            END) / a.balance) * 100
        ELSE 0
    END AS daily_return_pct,
    
    -- Instrument diversity
    COUNT(DISTINCT t.instrument_id) AS unique_instruments
FROM accounts a
JOIN trades t ON a.account_id = t.account_id
GROUP BY a.account_id, a.account_number, a.balance, DATE_TRUNC('day', t.executed_at)
ORDER BY a.account_id, trade_date DESC;

COMMENT ON VIEW v_daily_pnl_summary IS 'Daily P&L summary per account';

-- ============================================================================
-- View: Monthly P&L Summary
-- ============================================================================
CREATE OR REPLACE VIEW v_monthly_pnl_summary AS
SELECT 
    a.account_id,
    a.account_number,
    DATE_TRUNC('month', t.executed_at)::DATE AS month,
    
    -- Trade statistics
    COUNT(t.trade_id) AS total_trades,
    COUNT(DISTINCT DATE_TRUNC('day', t.executed_at)) AS trading_days,
    AVG(COUNT(t.trade_id)) OVER (
        PARTITION BY a.account_id, DATE_TRUNC('month', t.executed_at)
    ) AS avg_trades_per_day,
    
    -- Volume
    SUM(t.value) AS total_volume,
    AVG(t.value) AS avg_trade_value,
    
    -- Costs
    SUM(t.commission) AS total_commission,
    
    -- P&L
    SUM(CASE 
        WHEN t.side = 'sell' THEN t.value - t.commission
        ELSE -(t.value + t.commission)
    END) AS monthly_pnl,
    
    -- Profit metrics
    SUM(CASE 
        WHEN t.side = 'sell' AND (t.value - t.commission) > 0 THEN t.value - t.commission
        ELSE 0
    END) AS gross_profit,
    
    SUM(CASE 
        WHEN t.side = 'buy' OR (t.side = 'sell' AND (t.value - t.commission) < 0)
        THEN ABS(t.value + t.commission)
        ELSE 0
    END) AS gross_loss,
    
    -- Profit factor
    CASE 
        WHEN SUM(CASE 
            WHEN t.side = 'buy' OR (t.side = 'sell' AND (t.value - t.commission) < 0)
            THEN ABS(t.value + t.commission)
            ELSE 0
        END) > 0 THEN
            SUM(CASE 
                WHEN t.side = 'sell' AND (t.value - t.commission) > 0 
                THEN t.value - t.commission
                ELSE 0
            END) / 
            SUM(CASE 
                WHEN t.side = 'buy' OR (t.side = 'sell' AND (t.value - t.commission) < 0)
                THEN ABS(t.value + t.commission)
                ELSE 0
            END)
        ELSE NULL
    END AS profit_factor,
    
    -- Return percentage
    CASE 
        WHEN a.balance > 0 THEN
            (SUM(CASE 
                WHEN t.side = 'sell' THEN t.value - t.commission
                ELSE -(t.value + t.commission)
            END) / a.balance) * 100
        ELSE 0
    END AS monthly_return_pct
FROM accounts a
JOIN trades t ON a.account_id = t.account_id
GROUP BY a.account_id, a.account_number, a.balance, DATE_TRUNC('month', t.executed_at)
ORDER BY a.account_id, month DESC;

COMMENT ON VIEW v_monthly_pnl_summary IS 'Monthly P&L summary per account';

-- ============================================================================
-- View: Instrument P&L
-- ============================================================================
CREATE OR REPLACE VIEW v_instrument_pnl AS
SELECT 
    i.instrument_id,
    i.symbol,
    i.instrument_name,
    i.instrument_type,
    
    -- From closed positions
    COUNT(ph.position_id) AS closed_positions,
    SUM(ph.realized_pnl) AS total_realized_pnl,
    AVG(ph.realized_pnl) AS avg_realized_pnl,
    SUM(CASE WHEN ph.realized_pnl > 0 THEN ph.realized_pnl ELSE 0 END) AS gross_profit,
    SUM(CASE WHEN ph.realized_pnl < 0 THEN ABS(ph.realized_pnl) ELSE 0 END) AS gross_loss,
    
    -- Win/loss statistics
    COUNT(CASE WHEN ph.realized_pnl > 0 THEN 1 END) AS winning_positions,
    COUNT(CASE WHEN ph.realized_pnl < 0 THEN 1 END) AS losing_positions,
    CASE 
        WHEN COUNT(ph.position_id) > 0 THEN
            (COUNT(CASE WHEN ph.realized_pnl > 0 THEN 1 END)::DECIMAL / COUNT(ph.position_id)) * 100
        ELSE 0
    END AS win_rate,
    
    -- From open positions
    COUNT(p.position_id) AS open_positions,
    SUM(p.unrealized_pnl) AS total_unrealized_pnl,
    
    -- Total P&L
    COALESCE(SUM(ph.realized_pnl), 0) + COALESCE(SUM(p.unrealized_pnl), 0) AS total_pnl,
    
    -- Holding period
    AVG(EXTRACT(EPOCH FROM ph.holding_period) / 3600) AS avg_holding_hours,
    
    -- Best and worst trades
    MAX(ph.realized_pnl) AS best_trade,
    MIN(ph.realized_pnl) AS worst_trade
FROM instruments i
LEFT JOIN position_history ph ON i.instrument_id = ph.instrument_id
LEFT JOIN positions p ON i.instrument_id = p.instrument_id
WHERE i.is_tradeable = true
GROUP BY i.instrument_id, i.symbol, i.instrument_name, i.instrument_type;

COMMENT ON VIEW v_instrument_pnl IS 'P&L analysis by instrument';

-- ============================================================================
-- View: Cumulative P&L
-- ============================================================================
CREATE OR REPLACE VIEW v_cumulative_pnl AS
WITH daily_pnl AS (
    SELECT 
        t.account_id,
        DATE_TRUNC('day', t.executed_at)::DATE AS trade_date,
        SUM(CASE 
            WHEN t.side = 'sell' THEN t.value - t.commission
            ELSE -(t.value + t.commission)
        END) AS daily_pnl
    FROM trades t
    GROUP BY t.account_id, DATE_TRUNC('day', t.executed_at)
),
cumulative_calc AS (
    SELECT 
        a.account_id,
        a.account_number,
        d.trade_date,
        d.daily_pnl,
        SUM(d.daily_pnl) OVER (
            PARTITION BY a.account_id 
            ORDER BY d.trade_date
        ) AS cumulative_pnl,
        SUM(CASE WHEN d.daily_pnl > 0 THEN d.daily_pnl ELSE 0 END) OVER (
            PARTITION BY a.account_id 
            ORDER BY d.trade_date
        ) AS cumulative_profit,
        SUM(CASE WHEN d.daily_pnl < 0 THEN ABS(d.daily_pnl) ELSE 0 END) OVER (
            PARTITION BY a.account_id 
            ORDER BY d.trade_date
        ) AS cumulative_loss
    FROM accounts a
    JOIN daily_pnl d ON a.account_id = d.account_id
)
SELECT 
    account_id,
    account_number,
    trade_date,
    daily_pnl,
    cumulative_pnl,
    cumulative_profit,
    cumulative_loss,
    
    -- Running maximum
    MAX(cumulative_pnl) OVER (
        PARTITION BY account_id 
        ORDER BY trade_date
    ) AS running_max_pnl,
    
    -- Drawdown
    cumulative_pnl - MAX(cumulative_pnl) OVER (
        PARTITION BY account_id 
        ORDER BY trade_date
    ) AS drawdown
FROM cumulative_calc
ORDER BY account_id, trade_date;

COMMENT ON VIEW v_cumulative_pnl IS 'Cumulative P&L with drawdown analysis';

-- ============================================================================
-- View: Trade P&L Analysis
-- ============================================================================
CREATE OR REPLACE VIEW v_trade_pnl_analysis AS
SELECT 
    t.trade_id,
    t.account_id,
    a.account_number,
    t.instrument_id,
    i.symbol,
    t.order_id,
    t.side,
    t.quantity,
    t.price,
    t.value,
    t.commission,
    
    -- Net value
    CASE 
        WHEN t.side = 'sell' THEN t.value - t.commission
        ELSE -(t.value + t.commission)
    END AS net_value,
    
    -- Commission as percentage
    (t.commission / NULLIF(t.value, 0)) * 100 AS commission_pct,
    
    -- Execution quality
    t.executed_at,
    EXTRACT(EPOCH FROM (t.executed_at - o.created_at)) AS execution_time_seconds,
    
    -- Context
    DATE_TRUNC('day', t.executed_at)::DATE AS trade_date,
    EXTRACT(HOUR FROM t.executed_at) AS trade_hour,
    EXTRACT(DOW FROM t.executed_at) AS trade_day_of_week,
    
    -- Running totals for the day
    SUM(CASE 
        WHEN t.side = 'sell' THEN t.value - t.commission
        ELSE -(t.value + t.commission)
    END) OVER (
        PARTITION BY t.account_id, DATE_TRUNC('day', t.executed_at)
        ORDER BY t.executed_at
    ) AS running_daily_pnl
FROM trades t
JOIN accounts a ON t.account_id = a.account_id
JOIN instruments i ON t.instrument_id = i.instrument_id
JOIN orders o ON t.order_id = o.order_id
ORDER BY t.account_id, t.executed_at DESC;

COMMENT ON VIEW v_trade_pnl_analysis IS 'Detailed P&L analysis per trade';

-- ============================================================================
-- View: Account P&L History
-- ============================================================================
CREATE OR REPLACE VIEW v_account_pnl_history AS
SELECT 
    ph.account_id,
    a.account_number,
    ph.position_id,
    ph.instrument_id,
    i.symbol,
    i.instrument_name,
    ph.side,
    ph.quantity,
    ph.entry_price,
    ph.exit_price,
    ph.realized_pnl,
    
    -- Return metrics
    CASE 
        WHEN ph.entry_price > 0 THEN
            ((ph.exit_price - ph.entry_price) / ph.entry_price) * 100
        ELSE 0
    END AS return_pct,
    
    -- Position value
    ph.quantity * ph.entry_price AS entry_value,
    ph.quantity * ph.exit_price AS exit_value,
    
    -- Holding period
    ph.holding_period,
    EXTRACT(EPOCH FROM ph.holding_period) / 3600 AS holding_hours,
    EXTRACT(EPOCH FROM ph.holding_period) / 86400 AS holding_days,
    
    -- Annualized return (simplified)
    CASE 
        WHEN EXTRACT(EPOCH FROM ph.holding_period) > 0 AND ph.entry_price > 0 THEN
            (((ph.exit_price - ph.entry_price) / ph.entry_price) * 
             (31536000 / EXTRACT(EPOCH FROM ph.holding_period))) * 100
        ELSE NULL
    END AS annualized_return_pct,
    
    ph.opened_at,
    ph.closed_at
FROM position_history ph
JOIN accounts a ON ph.account_id = a.account_id
JOIN instruments i ON ph.instrument_id = i.instrument_id
ORDER BY ph.account_id, ph.closed_at DESC;

COMMENT ON VIEW v_account_pnl_history IS 'Historical P&L for closed positions';

-- ============================================================================
-- View: P&L by Trading Session
-- ============================================================================
CREATE OR REPLACE VIEW v_pnl_by_session AS
SELECT 
    a.account_id,
    a.account_number,
    DATE_TRUNC('day', t.executed_at)::DATE AS trade_date,
    CASE 
        WHEN EXTRACT(HOUR FROM t.executed_at) BETWEEN 0 AND 5 THEN 'Asian'
        WHEN EXTRACT(HOUR FROM t.executed_at) BETWEEN 6 AND 13 THEN 'European'
        WHEN EXTRACT(HOUR FROM t.executed_at) BETWEEN 14 AND 21 THEN 'US'
        ELSE 'After Hours'
    END AS trading_session,
    
    COUNT(t.trade_id) AS trades_count,
    SUM(t.value) AS total_volume,
    SUM(CASE 
        WHEN t.side = 'sell' THEN t.value - t.commission
        ELSE -(t.value + t.commission)
    END) AS session_pnl,
    
    AVG(t.price) AS avg_price,
    SUM(t.commission) AS total_commission
FROM accounts a
JOIN trades t ON a.account_id = t.account_id
GROUP BY a.account_id, a.account_number, 
         DATE_TRUNC('day', t.executed_at),
         CASE 
             WHEN EXTRACT(HOUR FROM t.executed_at) BETWEEN 0 AND 5 THEN 'Asian'
             WHEN EXTRACT(HOUR FROM t.executed_at) BETWEEN 6 AND 13 THEN 'European'
             WHEN EXTRACT(HOUR FROM t.executed_at) BETWEEN 14 AND 21 THEN 'US'
             ELSE 'After Hours'
         END
ORDER BY a.account_id, trade_date, trading_session;

COMMENT ON VIEW v_pnl_by_session IS 'P&L breakdown by trading session';
