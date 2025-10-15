-- ============================================================================
-- Performance Benchmark for Order Execution
-- Author: Gabriel Demetrios Lafis
-- Description: Benchmark tests for order placement and execution
-- ============================================================================

-- Setup test data
\timing on

-- Create temporary test accounts and instruments
DO $$
DECLARE
    v_user_id BIGINT;
    v_account_id BIGINT;
    v_instrument_id BIGINT;
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_order_count INTEGER := 1000;
    i INTEGER;
BEGIN
    RAISE NOTICE 'Starting performance benchmark...';
    
    -- Create test user
    INSERT INTO users (username, email, password_hash, kyc_status)
    VALUES ('bench_user', 'bench@test.com', 'hash123', 'approved')
    RETURNING user_id INTO v_user_id;
    
    -- Create test account with sufficient balance
    INSERT INTO accounts (user_id, account_number, account_type, balance, available_balance)
    VALUES (v_user_id, 'BENCH001', 'cash', 10000000, 10000000)
    RETURNING account_id INTO v_account_id;
    
    -- Create test instrument
    INSERT INTO instruments (symbol, instrument_name, instrument_type, exchange, 
                            currency, is_tradeable, min_trade_size)
    VALUES ('BENCH', 'Benchmark Stock', 'stock', 'TEST', 'USD', true, 1.0)
    RETURNING instrument_id INTO v_instrument_id;
    
    -- Create market ticker data
    INSERT INTO market_data_tickers (instrument_id, last_price, bid_price, ask_price, volume)
    VALUES (v_instrument_id, 100.00, 99.50, 100.50, 1000000);
    
    RAISE NOTICE 'Test data created. Account ID: %, Instrument ID: %', v_account_id, v_instrument_id;
    
    -- Benchmark: Place orders
    RAISE NOTICE 'Benchmarking order placement (%  orders)...', v_order_count;
    v_start_time := clock_timestamp();
    
    FOR i IN 1..v_order_count LOOP
        PERFORM place_order(
            p_account_id := v_account_id,
            p_instrument_id := v_instrument_id,
            p_order_type := 'limit',
            p_side := CASE WHEN i % 2 = 0 THEN 'buy' ELSE 'sell' END,
            p_quantity := 10.0,
            p_price := 100.00 + (random() * 10)
        );
    END LOOP;
    
    v_end_time := clock_timestamp();
    RAISE NOTICE 'Order placement completed in: %', v_end_time - v_start_time;
    RAISE NOTICE 'Average time per order: % ms', 
        EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000 / v_order_count;
    
    -- Benchmark: Query orders
    RAISE NOTICE 'Benchmarking order queries...';
    v_start_time := clock_timestamp();
    
    PERFORM COUNT(*) FROM orders WHERE account_id = v_account_id;
    
    v_end_time := clock_timestamp();
    RAISE NOTICE 'Order query completed in: %', v_end_time - v_start_time;
    
    -- Benchmark: Update positions
    RAISE NOTICE 'Benchmarking position updates...';
    v_start_time := clock_timestamp();
    
    FOR i IN 1..100 LOOP
        PERFORM update_position(
            p_account_id := v_account_id,
            p_instrument_id := v_instrument_id,
            p_side := 'buy',
            p_quantity := 10.0,
            p_price := 100.00 + (random() * 10)
        );
    END LOOP;
    
    v_end_time := clock_timestamp();
    RAISE NOTICE 'Position updates completed in: %', v_end_time - v_start_time;
    
    -- Cleanup
    DELETE FROM orders WHERE account_id = v_account_id;
    DELETE FROM positions WHERE account_id = v_account_id;
    DELETE FROM market_data_tickers WHERE instrument_id = v_instrument_id;
    DELETE FROM instruments WHERE instrument_id = v_instrument_id;
    DELETE FROM accounts WHERE account_id = v_account_id;
    DELETE FROM users WHERE user_id = v_user_id;
    
    RAISE NOTICE 'Benchmark completed and test data cleaned up.';
END $$;

\timing off

-- ============================================================================
-- Performance Metrics
-- ============================================================================

-- Table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    pg_total_relation_size(schemaname||'.'||tablename) AS bytes
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Index usage statistics
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

-- Cache hit ratio
SELECT 
    'cache hit ratio' AS metric,
    sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) AS ratio
FROM pg_statio_user_tables;
