-- ============================================================================
-- Daily Reports
-- Author: Gabriel Demetrios Lafis
-- Description: Standard daily reporting queries
-- ============================================================================

-- ============================================================================
-- Report: Daily Trading Summary
-- ============================================================================
SELECT 
    CURRENT_DATE AS report_date,
    COUNT(DISTINCT account_id) AS active_accounts,
    COUNT(*) AS total_trades,
    SUM(value) AS total_volume,
    SUM(commission) AS total_commission,
    COUNT(DISTINCT instrument_id) AS instruments_traded,
    AVG(value) AS avg_trade_size,
    MIN(executed_at) AS first_trade_time,
    MAX(executed_at) AS last_trade_time
FROM trades
WHERE DATE_TRUNC('day', executed_at) = CURRENT_DATE;

-- ============================================================================
-- Report: Account Balances
-- ============================================================================
SELECT 
    account_id,
    account_number,
    account_type,
    balance,
    available_balance,
    margin_used,
    balance - available_balance AS reserved_balance,
    (available_balance / NULLIF(balance, 0)) * 100 AS available_pct,
    updated_at
FROM accounts
WHERE is_active = true
ORDER BY balance DESC;

-- ============================================================================
-- Report: Open Positions Summary
-- ============================================================================
SELECT 
    account_id,
    account_number,
    COUNT(position_id) AS total_positions,
    SUM(quantity * current_price) AS total_exposure,
    SUM(unrealized_pnl) AS total_unrealized_pnl,
    SUM(CASE WHEN unrealized_pnl > 0 THEN 1 ELSE 0 END) AS winning_positions,
    SUM(CASE WHEN unrealized_pnl < 0 THEN 1 ELSE 0 END) AS losing_positions,
    AVG(unrealized_pnl) AS avg_position_pnl
FROM v_position_details
GROUP BY account_id, account_number
ORDER BY total_unrealized_pnl DESC;

-- ============================================================================
-- Report: Pending Orders
-- ============================================================================
SELECT 
    account_id,
    account_number,
    COUNT(*) AS pending_orders,
    SUM(quantity) AS total_quantity,
    SUM(quantity * COALESCE(price, stop_price, 0)) AS total_value,
    COUNT(CASE WHEN side = 'buy' THEN 1 END) AS buy_orders,
    COUNT(CASE WHEN side = 'sell' THEN 1 END) AS sell_orders,
    COUNT(CASE WHEN order_type = 'limit' THEN 1 END) AS limit_orders,
    COUNT(CASE WHEN order_type = 'market' THEN 1 END) AS market_orders
FROM v_order_book
WHERE status IN ('pending', 'partial')
GROUP BY account_id, account_number
ORDER BY pending_orders DESC;

-- ============================================================================
-- Report: Top Gainers/Losers Today
-- ============================================================================
SELECT 
    account_id,
    account_number,
    trade_date,
    total_trades,
    total_volume,
    daily_pnl,
    daily_return_pct,
    total_commission,
    unique_instruments
FROM v_daily_pnl_summary
WHERE trade_date = CURRENT_DATE
ORDER BY daily_pnl DESC
LIMIT 20;

-- ============================================================================
-- Report: Risk Alert Summary
-- ============================================================================
SELECT 
    'Margin Calls' AS alert_type,
    COUNT(*) AS count,
    SUM(margin_call_amount) AS total_amount
FROM v_margin_call_alerts
UNION ALL
SELECT 
    'Low Balance' AS alert_type,
    COUNT(*) AS count,
    NULL AS total_amount
FROM v_risk_metrics
WHERE low_balance_alert = true
UNION ALL
SELECT 
    'High Concentration' AS alert_type,
    COUNT(*) AS count,
    NULL AS total_amount
FROM v_risk_metrics
WHERE concentration_ratio > 50;

-- ============================================================================
-- Report: Instrument Trading Volume
-- ============================================================================
SELECT 
    i.symbol,
    i.instrument_name,
    i.instrument_type,
    COUNT(t.trade_id) AS trades_today,
    SUM(t.quantity) AS total_quantity,
    SUM(t.value) AS total_value,
    AVG(t.price) AS avg_price,
    MIN(t.price) AS low_price,
    MAX(t.price) AS high_price,
    COUNT(DISTINCT t.account_id) AS unique_traders
FROM instruments i
LEFT JOIN trades t ON i.instrument_id = t.instrument_id 
    AND DATE_TRUNC('day', t.executed_at) = CURRENT_DATE
WHERE i.is_tradeable = true
GROUP BY i.instrument_id, i.symbol, i.instrument_name, i.instrument_type
HAVING COUNT(t.trade_id) > 0
ORDER BY total_value DESC;

-- ============================================================================
-- Report: Settlement Summary
-- ============================================================================
SELECT 
    DATE_TRUNC('day', executed_at)::DATE AS settlement_date,
    COUNT(*) AS total_trades,
    COUNT(CASE WHEN settlement_status = 'settled' THEN 1 END) AS settled_trades,
    COUNT(CASE WHEN settlement_status = 'pending' THEN 1 END) AS pending_trades,
    COUNT(CASE WHEN settlement_status IS NULL THEN 1 END) AS unsettled_trades,
    SUM(value) AS total_value,
    SUM(commission) AS total_commission
FROM trades
WHERE DATE_TRUNC('day', executed_at) >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE_TRUNC('day', executed_at)
ORDER BY settlement_date DESC;
