-- ============================================================================
-- Load Test Script for pgbench
-- Author: Gabriel Demetrios Lafis
-- Description: Load testing script for order placement
-- ============================================================================

-- This script is designed to be run with pgbench:
-- pgbench -c 10 -j 2 -t 1000 -f tests/load/place_orders.sql trading_db

-- Random account and instrument IDs (should exist in database)
\set account_id random(1, 100)
\set instrument_id random(1, 50)
\set quantity random(1, 100)
\set price random(50, 150)
\set side random(0, 1)

-- Place order
SELECT place_order(
    p_account_id := :account_id,
    p_instrument_id := :instrument_id,
    p_order_type := 'limit',
    p_side := CASE WHEN :side = 0 THEN 'buy' ELSE 'sell' END,
    p_quantity := :quantity::DECIMAL,
    p_price := :price::DECIMAL
);
