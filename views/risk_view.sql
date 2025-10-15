-- ============================================================================
-- Risk Management Views
-- Author: Gabriel Demetrios Lafis
-- Description: Views for risk metrics and monitoring
-- ============================================================================

-- ============================================================================
-- View: Account Risk Metrics
-- ============================================================================
CREATE OR REPLACE VIEW v_risk_metrics AS
SELECT 
    a.account_id,
    a.account_number,
    a.account_type,
    a.balance,
    a.available_balance,
    a.margin_used,
    a.leverage,
    
    -- Position metrics
    COUNT(DISTINCT p.position_id) AS total_positions,
    COALESCE(SUM(p.quantity * p.current_price), 0) AS total_exposure,
    COALESCE(SUM(p.unrealized_pnl), 0) AS total_unrealized_pnl,
    
    -- Risk ratios
    CASE 
        WHEN a.balance > 0 THEN 
            (COALESCE(SUM(p.quantity * p.current_price), 0) / a.balance) * 100
        ELSE 0
    END AS exposure_ratio,
    
    CASE 
        WHEN a.balance > 0 THEN 
            (a.margin_used / a.balance) * 100
        ELSE 0
    END AS margin_usage_ratio,
    
    CASE 
        WHEN a.margin_used > 0 THEN 
            (a.balance / a.margin_used) * 100
        ELSE NULL
    END AS margin_level,
    
    -- Concentration risk
    MAX(p.quantity * p.current_price) AS largest_position_value,
    CASE 
        WHEN COALESCE(SUM(p.quantity * p.current_price), 0) > 0 THEN
            (MAX(p.quantity * p.current_price) / SUM(p.quantity * p.current_price)) * 100
        ELSE 0
    END AS concentration_ratio,
    
    -- Risk alerts
    CASE 
        WHEN a.account_type = 'margin' AND a.balance < a.margin_used THEN true
        ELSE false
    END AS margin_call_risk,
    
    CASE 
        WHEN a.available_balance < (a.balance * 0.1) THEN true
        ELSE false
    END AS low_balance_alert,
    
    a.updated_at
FROM accounts a
LEFT JOIN positions p ON a.account_id = p.account_id
WHERE a.is_active = true
GROUP BY a.account_id, a.account_number, a.account_type, a.balance, 
         a.available_balance, a.margin_used, a.leverage, a.updated_at;

COMMENT ON VIEW v_risk_metrics IS 'Comprehensive risk metrics per account';

-- ============================================================================
-- View: Position Risk Details
-- ============================================================================
CREATE OR REPLACE VIEW v_position_risk AS
SELECT 
    p.position_id,
    p.account_id,
    a.account_number,
    p.instrument_id,
    i.symbol,
    i.instrument_name,
    i.instrument_type,
    p.side,
    p.quantity,
    p.average_entry_price,
    p.current_price,
    p.unrealized_pnl,
    
    -- Position value
    p.quantity * p.current_price AS position_value,
    
    -- Risk metrics
    p.margin_used,
    CASE 
        WHEN a.balance > 0 THEN 
            ((p.quantity * p.current_price) / a.balance) * 100
        ELSE 0
    END AS position_size_pct,
    
    CASE 
        WHEN p.average_entry_price > 0 THEN 
            (p.unrealized_pnl / (p.average_entry_price * p.quantity)) * 100
        ELSE 0
    END AS unrealized_pnl_pct,
    
    -- Stop loss and take profit levels
    CASE 
        WHEN p.side = 'long' THEN p.average_entry_price * 0.98
        ELSE p.average_entry_price * 1.02
    END AS suggested_stop_loss,
    
    CASE 
        WHEN p.side = 'long' THEN p.average_entry_price * 1.02
        ELSE p.average_entry_price * 0.98
    END AS suggested_take_profit,
    
    -- Volatility estimation (simplified)
    i.volatility AS instrument_volatility,
    
    -- VaR estimation (simplified, 95% confidence, 1-day)
    CASE 
        WHEN i.volatility IS NOT NULL THEN
            (p.quantity * p.current_price) * i.volatility * 1.65
        ELSE NULL
    END AS value_at_risk_95,
    
    -- Holding period
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.opened_at)) / 3600 AS holding_hours,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.opened_at)) / 86400 AS holding_days,
    
    p.opened_at,
    p.updated_at
FROM positions p
JOIN accounts a ON p.account_id = a.account_id
JOIN instruments i ON p.instrument_id = i.instrument_id;

COMMENT ON VIEW v_position_risk IS 'Detailed risk analysis per position';

-- ============================================================================
-- View: Portfolio Diversification
-- ============================================================================
CREATE OR REPLACE VIEW v_portfolio_diversification AS
SELECT 
    a.account_id,
    a.account_number,
    i.instrument_type,
    COUNT(DISTINCT p.position_id) AS positions_count,
    SUM(p.quantity * p.current_price) AS total_value,
    SUM(p.unrealized_pnl) AS total_unrealized_pnl,
    AVG(p.unrealized_pnl / NULLIF(p.average_entry_price * p.quantity, 0) * 100) AS avg_return_pct,
    
    -- Percentage of portfolio
    CASE 
        WHEN SUM(SUM(p.quantity * p.current_price)) OVER (PARTITION BY a.account_id) > 0 THEN
            (SUM(p.quantity * p.current_price) / 
             SUM(SUM(p.quantity * p.current_price)) OVER (PARTITION BY a.account_id)) * 100
        ELSE 0
    END AS portfolio_percentage
FROM accounts a
JOIN positions p ON a.account_id = p.account_id
JOIN instruments i ON p.instrument_id = i.instrument_id
WHERE a.is_active = true
GROUP BY a.account_id, a.account_number, i.instrument_type;

COMMENT ON VIEW v_portfolio_diversification IS 'Portfolio diversification by instrument type';

-- ============================================================================
-- View: Order Risk Analysis
-- ============================================================================
CREATE OR REPLACE VIEW v_order_risk AS
SELECT 
    o.order_id,
    o.account_id,
    a.account_number,
    o.instrument_id,
    i.symbol,
    o.order_type,
    o.side,
    o.quantity,
    o.price,
    o.stop_price,
    o.status,
    
    -- Order value
    o.quantity * COALESCE(o.price, o.stop_price, 0) AS order_value,
    
    -- Risk metrics
    CASE 
        WHEN a.balance > 0 THEN 
            ((o.quantity * COALESCE(o.price, o.stop_price, 0)) / a.balance) * 100
        ELSE 0
    END AS order_size_pct,
    
    -- Impact on available balance
    CASE 
        WHEN o.side = 'buy' THEN
            a.available_balance - (o.quantity * COALESCE(o.price, o.stop_price, 0))
        ELSE a.available_balance
    END AS balance_after_execution,
    
    -- Risk flags
    CASE 
        WHEN o.side = 'buy' AND 
             (o.quantity * COALESCE(o.price, o.stop_price, 0)) > a.available_balance 
        THEN true
        ELSE false
    END AS insufficient_balance,
    
    CASE 
        WHEN (o.quantity * COALESCE(o.price, o.stop_price, 0)) > (a.balance * 0.1)
        THEN true
        ELSE false
    END AS large_order_flag,
    
    o.created_at,
    o.updated_at
FROM orders o
JOIN accounts a ON o.account_id = a.account_id
JOIN instruments i ON o.instrument_id = i.instrument_id
WHERE o.status IN ('pending', 'partial');

COMMENT ON VIEW v_order_risk IS 'Risk analysis for active orders';

-- ============================================================================
-- View: Exposure by Instrument
-- ============================================================================
CREATE OR REPLACE VIEW v_exposure_by_instrument AS
SELECT 
    i.instrument_id,
    i.symbol,
    i.instrument_name,
    i.instrument_type,
    
    -- Long exposure
    COALESCE(SUM(CASE WHEN p.side = 'long' THEN p.quantity * p.current_price ELSE 0 END), 0) AS long_exposure,
    COUNT(CASE WHEN p.side = 'long' THEN 1 END) AS long_positions,
    
    -- Short exposure
    COALESCE(SUM(CASE WHEN p.side = 'short' THEN p.quantity * p.current_price ELSE 0 END), 0) AS short_exposure,
    COUNT(CASE WHEN p.side = 'short' THEN 1 END) AS short_positions,
    
    -- Net exposure
    COALESCE(SUM(
        CASE 
            WHEN p.side = 'long' THEN p.quantity * p.current_price
            WHEN p.side = 'short' THEN -(p.quantity * p.current_price)
            ELSE 0
        END
    ), 0) AS net_exposure,
    
    -- Total exposure (absolute)
    COALESCE(SUM(p.quantity * p.current_price), 0) AS total_exposure,
    
    -- Unique accounts trading this instrument
    COUNT(DISTINCT p.account_id) AS unique_accounts,
    
    -- P&L
    COALESCE(SUM(p.unrealized_pnl), 0) AS total_unrealized_pnl
FROM instruments i
LEFT JOIN positions p ON i.instrument_id = p.instrument_id
WHERE i.is_tradeable = true
GROUP BY i.instrument_id, i.symbol, i.instrument_name, i.instrument_type;

COMMENT ON VIEW v_exposure_by_instrument IS 'Market exposure analysis by instrument';

-- ============================================================================
-- View: Margin Call Alerts
-- ============================================================================
CREATE OR REPLACE VIEW v_margin_call_alerts AS
SELECT 
    a.account_id,
    a.account_number,
    a.balance,
    a.margin_used,
    a.leverage,
    
    -- Margin metrics
    CASE 
        WHEN a.margin_used > 0 THEN 
            (a.balance / a.margin_used) * 100
        ELSE NULL
    END AS margin_level,
    
    -- Required deposits
    GREATEST(a.margin_used - a.balance, 0) AS margin_call_amount,
    
    -- Alert severity
    CASE 
        WHEN a.balance < a.margin_used * 0.5 THEN 'CRITICAL'
        WHEN a.balance < a.margin_used * 0.7 THEN 'HIGH'
        WHEN a.balance < a.margin_used * 0.9 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS alert_severity,
    
    -- Total positions at risk
    COUNT(p.position_id) AS positions_at_risk,
    COALESCE(SUM(p.quantity * p.current_price), 0) AS total_exposure,
    
    a.updated_at AS last_update
FROM accounts a
LEFT JOIN positions p ON a.account_id = p.account_id
WHERE a.is_active = true
    AND a.account_type = 'margin'
    AND a.balance < a.margin_used
GROUP BY a.account_id, a.account_number, a.balance, a.margin_used, a.leverage, a.updated_at;

COMMENT ON VIEW v_margin_call_alerts IS 'Active margin call alerts';

-- ============================================================================
-- View: Risk-Adjusted Returns
-- ============================================================================
CREATE OR REPLACE VIEW v_risk_adjusted_returns AS
WITH account_stats AS (
    SELECT 
        ph.account_id,
        COUNT(*) AS total_trades,
        AVG(ph.realized_pnl) AS avg_pnl,
        STDDEV(ph.realized_pnl) AS pnl_stddev,
        SUM(ph.realized_pnl) AS total_pnl,
        SUM(CASE WHEN ph.realized_pnl > 0 THEN ph.realized_pnl ELSE 0 END) AS gross_profit,
        SUM(CASE WHEN ph.realized_pnl < 0 THEN ABS(ph.realized_pnl) ELSE 0 END) AS gross_loss,
        MAX(ph.realized_pnl) AS max_win,
        MIN(ph.realized_pnl) AS max_loss
    FROM position_history ph
    GROUP BY ph.account_id
)
SELECT 
    a.account_id,
    a.account_number,
    a.balance,
    s.total_trades,
    s.total_pnl,
    s.avg_pnl,
    s.pnl_stddev,
    
    -- Sharpe-like ratio (simplified)
    CASE 
        WHEN s.pnl_stddev > 0 THEN s.avg_pnl / s.pnl_stddev
        ELSE NULL
    END AS risk_adjusted_return,
    
    -- Profit factor
    CASE 
        WHEN s.gross_loss > 0 THEN s.gross_profit / s.gross_loss
        ELSE NULL
    END AS profit_factor,
    
    -- Max favorable/adverse excursion ratio
    CASE 
        WHEN s.max_loss < 0 THEN ABS(s.max_win / s.max_loss)
        ELSE NULL
    END AS max_excursion_ratio,
    
    -- Recovery factor (total profit / max loss)
    CASE 
        WHEN s.max_loss < 0 THEN s.total_pnl / ABS(s.max_loss)
        ELSE NULL
    END AS recovery_factor
FROM accounts a
JOIN account_stats s ON a.account_id = s.account_id
WHERE a.is_active = true;

COMMENT ON VIEW v_risk_adjusted_returns IS 'Risk-adjusted performance metrics';
