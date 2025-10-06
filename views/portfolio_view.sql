-- ============================================================================
-- Portfolio and Reporting Views
-- Author: Gabriel Demetrios Lafis
-- Description: Views for portfolio aggregation and reporting
-- ============================================================================

-- ============================================================================
-- View: Portfolio Summary
-- ============================================================================
CREATE OR REPLACE VIEW v_portfolio_summary AS
SELECT 
    a.account_id,
    a.account_number,
    a.account_type,
    a.currency,
    a.balance AS cash_balance,
    a.available_balance,
    COALESCE(SUM(p.quantity * p.current_price), 0) AS positions_value,
    a.balance + COALESCE(SUM(p.quantity * p.current_price), 0) AS total_equity,
    COALESCE(SUM(p.unrealized_pnl), 0) AS total_unrealized_pnl,
    COALESCE(SUM(p.realized_pnl), 0) AS total_realized_pnl,
    COALESCE(SUM(p.unrealized_pnl + p.realized_pnl), 0) AS total_pnl,
    COUNT(p.position_id) AS open_positions_count,
    a.updated_at
FROM accounts a
LEFT JOIN positions p ON a.account_id = p.account_id
WHERE a.is_active = true
GROUP BY a.account_id, a.account_number, a.account_type, a.currency, 
         a.balance, a.available_balance, a.updated_at;

COMMENT ON VIEW v_portfolio_summary IS 'Portfolio summary with equity and P&L';

-- ============================================================================
-- View: Position Details
-- ============================================================================
CREATE OR REPLACE VIEW v_position_details AS
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
    p.realized_pnl,
    p.total_pnl,
    CASE 
        WHEN p.average_entry_price > 0 THEN 
            (p.unrealized_pnl / (p.average_entry_price * p.quantity)) * 100
        ELSE 0
    END AS pnl_percentage,
    p.quantity * p.current_price AS position_value,
    p.margin_used,
    p.opened_at,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.opened_at)) / 3600 AS holding_hours,
    p.updated_at
FROM positions p
JOIN accounts a ON p.account_id = a.account_id
JOIN instruments i ON p.instrument_id = i.instrument_id;

COMMENT ON VIEW v_position_details IS 'Detailed view of all open positions';

-- ============================================================================
-- View: Order Book
-- ============================================================================
CREATE OR REPLACE VIEW v_order_book AS
SELECT 
    o.order_id,
    o.account_id,
    a.account_number,
    o.instrument_id,
    i.symbol,
    i.instrument_name,
    o.order_type,
    o.side,
    o.quantity,
    o.filled_quantity,
    o.quantity - o.filled_quantity AS remaining_quantity,
    CASE 
        WHEN o.quantity > 0 THEN 
            (o.filled_quantity / o.quantity) * 100
        ELSE 0
    END AS fill_percentage,
    o.price,
    o.stop_price,
    o.average_fill_price,
    o.time_in_force,
    o.status,
    o.commission,
    o.client_order_id,
    o.created_at,
    o.updated_at,
    o.filled_at,
    o.cancelled_at,
    CASE 
        WHEN o.filled_at IS NOT NULL THEN 
            EXTRACT(EPOCH FROM (o.filled_at - o.created_at))
        ELSE NULL
    END AS execution_time_seconds
FROM orders o
JOIN accounts a ON o.account_id = a.account_id
JOIN instruments i ON o.instrument_id = i.instrument_id;

COMMENT ON VIEW v_order_book IS 'Detailed view of all orders';

-- ============================================================================
-- View: Trade History
-- ============================================================================
CREATE OR REPLACE VIEW v_trade_history AS
SELECT 
    t.trade_id,
    t.order_id,
    o.client_order_id,
    t.account_id,
    a.account_number,
    t.instrument_id,
    i.symbol,
    i.instrument_name,
    t.side,
    t.quantity,
    t.price,
    t.value,
    t.commission,
    t.value + t.commission AS total_cost,
    t.trade_type,
    t.executed_at,
    DATE_TRUNC('day', t.executed_at) AS trade_date
FROM trades t
JOIN orders o ON t.order_id = o.order_id
JOIN accounts a ON t.account_id = a.account_id
JOIN instruments i ON t.instrument_id = i.instrument_id;

COMMENT ON VIEW v_trade_history IS 'Detailed trade history with metadata';

-- ============================================================================
-- View: Daily P&L
-- ============================================================================
CREATE OR REPLACE VIEW v_daily_pnl AS
SELECT 
    a.account_id,
    a.account_number,
    DATE_TRUNC('day', t.executed_at) AS trade_date,
    COUNT(DISTINCT t.trade_id) AS trades_count,
    SUM(CASE WHEN t.side = 'buy' THEN t.quantity ELSE 0 END) AS total_bought,
    SUM(CASE WHEN t.side = 'sell' THEN t.quantity ELSE 0 END) AS total_sold,
    SUM(t.value) AS total_volume,
    SUM(t.commission) AS total_commission,
    SUM(CASE 
        WHEN t.side = 'sell' THEN t.value - t.commission
        ELSE -(t.value + t.commission)
    END) AS realized_pnl
FROM trades t
JOIN accounts a ON t.account_id = a.account_id
GROUP BY a.account_id, a.account_number, DATE_TRUNC('day', t.executed_at);

COMMENT ON VIEW v_daily_pnl IS 'Daily P&L aggregation';

-- ============================================================================
-- View: Performance Metrics
-- ============================================================================
CREATE OR REPLACE VIEW v_performance_metrics AS
WITH closed_positions AS (
    SELECT 
        account_id,
        COUNT(*) AS total_trades,
        COUNT(*) FILTER (WHERE realized_pnl > 0) AS winning_trades,
        COUNT(*) FILTER (WHERE realized_pnl < 0) AS losing_trades,
        SUM(realized_pnl) AS total_pnl,
        SUM(CASE WHEN realized_pnl > 0 THEN realized_pnl ELSE 0 END) AS gross_profit,
        SUM(CASE WHEN realized_pnl < 0 THEN ABS(realized_pnl) ELSE 0 END) AS gross_loss,
        AVG(realized_pnl) AS average_pnl,
        MAX(realized_pnl) AS best_trade,
        MIN(realized_pnl) AS worst_trade,
        AVG(EXTRACT(EPOCH FROM holding_period) / 3600) AS avg_holding_hours
    FROM position_history
    GROUP BY account_id
)
SELECT 
    a.account_id,
    a.account_number,
    cp.total_trades,
    cp.winning_trades,
    cp.losing_trades,
    CASE 
        WHEN cp.total_trades > 0 THEN 
            (cp.winning_trades::DECIMAL / cp.total_trades) * 100
        ELSE 0
    END AS win_rate,
    cp.total_pnl,
    cp.gross_profit,
    cp.gross_loss,
    CASE 
        WHEN cp.gross_loss > 0 THEN 
            cp.gross_profit / cp.gross_loss
        ELSE NULL
    END AS profit_factor,
    cp.average_pnl,
    cp.best_trade,
    cp.worst_trade,
    cp.avg_holding_hours
FROM accounts a
LEFT JOIN closed_positions cp ON a.account_id = cp.account_id
WHERE a.is_active = true;

COMMENT ON VIEW v_performance_metrics IS 'Trading performance metrics per account';

-- ============================================================================
-- View: Instrument Performance
-- ============================================================================
CREATE OR REPLACE VIEW v_instrument_performance AS
SELECT 
    i.instrument_id,
    i.symbol,
    i.instrument_name,
    i.instrument_type,
    COUNT(DISTINCT t.trade_id) AS total_trades,
    SUM(t.quantity) AS total_volume,
    SUM(t.value) AS total_value,
    AVG(t.price) AS average_price,
    MIN(t.price) AS min_price,
    MAX(t.price) AS max_price,
    COUNT(DISTINCT t.account_id) AS unique_traders,
    MAX(t.executed_at) AS last_trade_at
FROM instruments i
LEFT JOIN trades t ON i.instrument_id = t.instrument_id
WHERE i.is_tradeable = true
GROUP BY i.instrument_id, i.symbol, i.instrument_name, i.instrument_type;

COMMENT ON VIEW v_instrument_performance IS 'Trading activity per instrument';
