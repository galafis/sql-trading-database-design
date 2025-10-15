-- ============================================================================
-- P&L Calculation Functions
-- Author: Gabriel Demetrios Lafis
-- Description: Functions for calculating profit and loss
-- ============================================================================

-- ============================================================================
-- Function: Calculate Realized P&L
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_realized_pnl(
    p_entry_price DECIMAL,
    p_exit_price DECIMAL,
    p_quantity DECIMAL,
    p_side VARCHAR,
    p_commission DECIMAL DEFAULT 0
)
RETURNS DECIMAL AS $$
DECLARE
    v_pnl DECIMAL;
BEGIN
    -- Calculate P&L based on position side
    IF p_side = 'long' THEN
        v_pnl := (p_exit_price - p_entry_price) * p_quantity - p_commission;
    ELSIF p_side = 'short' THEN
        v_pnl := (p_entry_price - p_exit_price) * p_quantity - p_commission;
    ELSE
        RAISE EXCEPTION 'Invalid side: %', p_side;
    END IF;
    
    RETURN v_pnl;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION calculate_realized_pnl IS 'Calculate realized P&L for a closed position';

-- ============================================================================
-- Function: Calculate Unrealized P&L
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_unrealized_pnl(
    p_entry_price DECIMAL,
    p_current_price DECIMAL,
    p_quantity DECIMAL,
    p_side VARCHAR
)
RETURNS DECIMAL AS $$
DECLARE
    v_pnl DECIMAL;
BEGIN
    -- Calculate unrealized P&L based on position side
    IF p_side = 'long' THEN
        v_pnl := (p_current_price - p_entry_price) * p_quantity;
    ELSIF p_side = 'short' THEN
        v_pnl := (p_entry_price - p_current_price) * p_quantity;
    ELSE
        RAISE EXCEPTION 'Invalid side: %', p_side;
    END IF;
    
    RETURN v_pnl;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION calculate_unrealized_pnl IS 'Calculate unrealized P&L for an open position';

-- ============================================================================
-- Function: Calculate P&L Percentage
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_pnl_percentage(
    p_pnl DECIMAL,
    p_entry_price DECIMAL,
    p_quantity DECIMAL
)
RETURNS DECIMAL AS $$
DECLARE
    v_initial_value DECIMAL;
BEGIN
    v_initial_value := p_entry_price * p_quantity;
    
    IF v_initial_value = 0 THEN
        RETURN 0;
    END IF;
    
    RETURN (p_pnl / v_initial_value) * 100;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION calculate_pnl_percentage IS 'Calculate P&L as percentage of initial position value';

-- ============================================================================
-- Function: Get Account Daily P&L
-- ============================================================================
CREATE OR REPLACE FUNCTION get_account_daily_pnl(
    p_account_id BIGINT,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    trade_date DATE,
    trades_count BIGINT,
    total_volume DECIMAL,
    total_commission DECIMAL,
    realized_pnl DECIMAL,
    gross_profit DECIMAL,
    gross_loss DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p_date AS trade_date,
        COUNT(t.trade_id) AS trades_count,
        SUM(t.value) AS total_volume,
        SUM(t.commission) AS total_commission,
        SUM(CASE 
            WHEN t.side = 'sell' THEN t.value - t.commission
            ELSE -(t.value + t.commission)
        END) AS realized_pnl,
        SUM(CASE 
            WHEN t.side = 'sell' AND (t.value - t.commission) > 0 THEN t.value - t.commission
            ELSE 0
        END) AS gross_profit,
        SUM(CASE 
            WHEN t.side = 'buy' OR (t.side = 'sell' AND (t.value - t.commission) < 0) 
            THEN ABS(t.value + t.commission)
            ELSE 0
        END) AS gross_loss
    FROM trades t
    WHERE t.account_id = p_account_id
        AND DATE_TRUNC('day', t.executed_at) = p_date;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_account_daily_pnl IS 'Get daily P&L summary for an account';

-- ============================================================================
-- Function: Get Account Period P&L
-- ============================================================================
CREATE OR REPLACE FUNCTION get_account_period_pnl(
    p_account_id BIGINT,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    trade_date DATE,
    trades_count BIGINT,
    total_volume DECIMAL,
    total_commission DECIMAL,
    realized_pnl DECIMAL,
    cumulative_pnl DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    WITH daily_pnl AS (
        SELECT 
            DATE_TRUNC('day', t.executed_at)::DATE AS trade_date,
            COUNT(t.trade_id) AS trades_count,
            SUM(t.value) AS total_volume,
            SUM(t.commission) AS total_commission,
            SUM(CASE 
                WHEN t.side = 'sell' THEN t.value - t.commission
                ELSE -(t.value + t.commission)
            END) AS realized_pnl
        FROM trades t
        WHERE t.account_id = p_account_id
            AND DATE_TRUNC('day', t.executed_at) BETWEEN p_start_date AND p_end_date
        GROUP BY DATE_TRUNC('day', t.executed_at)
    )
    SELECT 
        d.trade_date,
        d.trades_count,
        d.total_volume,
        d.total_commission,
        d.realized_pnl,
        SUM(d.realized_pnl) OVER (ORDER BY d.trade_date) AS cumulative_pnl
    FROM daily_pnl d
    ORDER BY d.trade_date;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_account_period_pnl IS 'Get P&L summary for a date range with cumulative totals';

-- ============================================================================
-- Function: Calculate Profit Factor
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_profit_factor(
    p_account_id BIGINT,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS DECIMAL AS $$
DECLARE
    v_gross_profit DECIMAL;
    v_gross_loss DECIMAL;
BEGIN
    SELECT 
        SUM(CASE WHEN realized_pnl > 0 THEN realized_pnl ELSE 0 END),
        SUM(CASE WHEN realized_pnl < 0 THEN ABS(realized_pnl) ELSE 0 END)
    INTO v_gross_profit, v_gross_loss
    FROM position_history
    WHERE account_id = p_account_id
        AND (p_start_date IS NULL OR opened_at >= p_start_date)
        AND (p_end_date IS NULL OR opened_at <= p_end_date);
    
    IF v_gross_loss IS NULL OR v_gross_loss = 0 THEN
        RETURN NULL;
    END IF;
    
    RETURN v_gross_profit / v_gross_loss;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_profit_factor IS 'Calculate profit factor (gross profit / gross loss)';

-- ============================================================================
-- Function: Calculate Win Rate
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_win_rate(
    p_account_id BIGINT,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS DECIMAL AS $$
DECLARE
    v_total_trades BIGINT;
    v_winning_trades BIGINT;
BEGIN
    SELECT 
        COUNT(*),
        COUNT(*) FILTER (WHERE realized_pnl > 0)
    INTO v_total_trades, v_winning_trades
    FROM position_history
    WHERE account_id = p_account_id
        AND (p_start_date IS NULL OR opened_at >= p_start_date)
        AND (p_end_date IS NULL OR opened_at <= p_end_date);
    
    IF v_total_trades = 0 THEN
        RETURN 0;
    END IF;
    
    RETURN (v_winning_trades::DECIMAL / v_total_trades) * 100;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_win_rate IS 'Calculate win rate percentage';

-- ============================================================================
-- Function: Get Account Drawdown
-- ============================================================================
CREATE OR REPLACE FUNCTION get_account_drawdown(
    p_account_id BIGINT
)
RETURNS TABLE (
    current_drawdown DECIMAL,
    max_drawdown DECIMAL,
    max_drawdown_date TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    WITH equity_curve AS (
        SELECT 
            executed_at,
            SUM(CASE 
                WHEN side = 'sell' THEN value - commission
                ELSE -(value + commission)
            END) OVER (ORDER BY executed_at) AS cumulative_pnl
        FROM trades
        WHERE account_id = p_account_id
    ),
    running_max AS (
        SELECT 
            executed_at,
            cumulative_pnl,
            MAX(cumulative_pnl) OVER (ORDER BY executed_at) AS peak_pnl
        FROM equity_curve
    )
    SELECT 
        COALESCE((SELECT cumulative_pnl - peak_pnl 
         FROM running_max 
         ORDER BY executed_at DESC 
         LIMIT 1), 0) AS current_drawdown,
        COALESCE(MIN(cumulative_pnl - peak_pnl), 0) AS max_drawdown,
        (SELECT executed_at 
         FROM running_max 
         WHERE cumulative_pnl - peak_pnl = MIN(cumulative_pnl - peak_pnl) 
         LIMIT 1) AS max_drawdown_date
    FROM running_max;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_account_drawdown IS 'Calculate current and maximum drawdown for an account';

-- ============================================================================
-- Function: Calculate Sharpe Ratio
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_sharpe_ratio(
    p_account_id BIGINT,
    p_risk_free_rate DECIMAL DEFAULT 0.02,
    p_periods_per_year INTEGER DEFAULT 252
)
RETURNS DECIMAL AS $$
DECLARE
    v_avg_return DECIMAL;
    v_std_dev DECIMAL;
    v_sharpe_ratio DECIMAL;
BEGIN
    WITH daily_returns AS (
        SELECT 
            DATE_TRUNC('day', executed_at)::DATE AS trade_date,
            SUM(CASE 
                WHEN side = 'sell' THEN value - commission
                ELSE -(value + commission)
            END) AS daily_pnl
        FROM trades
        WHERE account_id = p_account_id
        GROUP BY DATE_TRUNC('day', executed_at)
    )
    SELECT 
        AVG(daily_pnl),
        STDDEV(daily_pnl)
    INTO v_avg_return, v_std_dev
    FROM daily_returns;
    
    IF v_std_dev IS NULL OR v_std_dev = 0 THEN
        RETURN NULL;
    END IF;
    
    v_sharpe_ratio := ((v_avg_return * p_periods_per_year) - p_risk_free_rate) / 
                      (v_std_dev * SQRT(p_periods_per_year));
    
    RETURN v_sharpe_ratio;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_sharpe_ratio IS 'Calculate annualized Sharpe ratio';
