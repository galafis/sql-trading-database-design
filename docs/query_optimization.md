# Query Optimization Guide

## Overview

This guide provides best practices and techniques for optimizing query performance in the trading database system.

---

## Index Optimization

### Using Indexes Effectively

**Good Examples:**
```sql
-- Uses idx_orders_account_id
SELECT * FROM orders WHERE account_id = 123;

-- Uses idx_orders_created_at
SELECT * FROM orders 
WHERE created_at >= '2024-01-01' 
ORDER BY created_at DESC;

-- Composite index usage
CREATE INDEX idx_orders_account_status ON orders(account_id, status);
SELECT * FROM orders WHERE account_id = 123 AND status = 'pending';
```

**Bad Examples (Index Not Used):**
```sql
-- Function on indexed column prevents index usage
SELECT * FROM orders WHERE UPPER(status) = 'PENDING';

-- Leading wildcard prevents index usage
SELECT * FROM instruments WHERE symbol LIKE '%AAPL';

-- OR conditions may prevent index usage
SELECT * FROM orders WHERE account_id = 123 OR instrument_id = 456;
```

### Recommended Indexes

```sql
-- Core indexes for frequent queries
CREATE INDEX idx_orders_account_status ON orders(account_id, status);
CREATE INDEX idx_orders_instrument_status ON orders(instrument_id, status);
CREATE INDEX idx_trades_executed_at_account ON trades(executed_at DESC, account_id);
CREATE INDEX idx_positions_account_instrument ON positions(account_id, instrument_id);

-- Partial indexes for specific use cases
CREATE INDEX idx_orders_pending ON orders(account_id, created_at) 
WHERE status IN ('pending', 'partial');

CREATE INDEX idx_positions_open ON positions(account_id) 
WHERE quantity > 0;
```

---

## Query Pattern Optimization

### 1. Use EXPLAIN ANALYZE

Always analyze query performance before optimization:

```sql
EXPLAIN ANALYZE
SELECT * FROM orders 
WHERE account_id = 123 
AND status = 'pending'
ORDER BY created_at DESC;
```

Look for:
- **Seq Scan**: Full table scans (bad for large tables)
- **Index Scan**: Good
- **Bitmap Heap Scan**: Good for medium selectivity
- **Cost**: Lower is better
- **Rows**: Actual vs estimated (large differences indicate statistics issues)

### 2. Avoid SELECT *

**Bad:**
```sql
SELECT * FROM trades WHERE account_id = 123;
```

**Good:**
```sql
SELECT trade_id, instrument_id, quantity, price, executed_at 
FROM trades 
WHERE account_id = 123;
```

### 3. Use LIMIT for Large Result Sets

**Bad:**
```sql
SELECT * FROM trades ORDER BY executed_at DESC;
```

**Good:**
```sql
SELECT * FROM trades 
ORDER BY executed_at DESC 
LIMIT 100;
```

### 4. Optimize JOINs

**Use appropriate JOIN types:**
```sql
-- INNER JOIN for required relationships
SELECT o.*, i.symbol 
FROM orders o
INNER JOIN instruments i ON o.instrument_id = i.instrument_id;

-- LEFT JOIN when right table might not have matches
SELECT a.*, COUNT(p.position_id) as position_count
FROM accounts a
LEFT JOIN positions p ON a.account_id = p.account_id
GROUP BY a.account_id;
```

**Join order matters:**
```sql
-- Good: Join smallest tables first
SELECT t.*
FROM trades t
JOIN orders o ON t.order_id = o.order_id  -- orders is smaller
JOIN accounts a ON t.account_id = a.account_id  -- accounts is smallest
WHERE a.account_type = 'cash';
```

---

## Aggregation Optimization

### 1. Use GROUP BY Efficiently

**Bad:**
```sql
SELECT account_id, SUM(value), COUNT(*), AVG(price)
FROM trades
GROUP BY account_id;
```

**Better with filtering:**
```sql
SELECT account_id, SUM(value), COUNT(*), AVG(price)
FROM trades
WHERE executed_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY account_id;
```

### 2. Use Window Functions Instead of Subqueries

**Bad:**
```sql
SELECT 
    t.*,
    (SELECT AVG(price) FROM trades t2 WHERE t2.account_id = t.account_id) as avg_price
FROM trades t;
```

**Good:**
```sql
SELECT 
    t.*,
    AVG(price) OVER (PARTITION BY account_id) as avg_price
FROM trades t;
```

### 3. Use FILTER for Conditional Aggregates

**Bad:**
```sql
SELECT 
    account_id,
    SUM(CASE WHEN side = 'buy' THEN value ELSE 0 END) as buy_value,
    SUM(CASE WHEN side = 'sell' THEN value ELSE 0 END) as sell_value
FROM trades
GROUP BY account_id;
```

**Good:**
```sql
SELECT 
    account_id,
    SUM(value) FILTER (WHERE side = 'buy') as buy_value,
    SUM(value) FILTER (WHERE side = 'sell') as sell_value
FROM trades
GROUP BY account_id;
```

---

## TimescaleDB Optimization

### 1. Use Time-Based Queries

**Good:**
```sql
SELECT * FROM market_data_ohlcv
WHERE time >= NOW() - INTERVAL '7 days'
AND instrument_id = 123;
```

### 2. Enable Compression

```sql
-- Enable compression for old data
ALTER TABLE market_data_ohlcv SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'instrument_id,timeframe',
    timescaledb.compress_orderby = 'time DESC'
);

-- Add compression policy
SELECT add_compression_policy('market_data_ohlcv', INTERVAL '7 days');
```

### 3. Use Continuous Aggregates

```sql
-- Pre-compute hourly aggregates
CREATE MATERIALIZED VIEW market_data_ohlcv_1h
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS time,
    instrument_id,
    first(open, time) AS open,
    max(high) AS high,
    min(low) AS low,
    last(close, time) AS close,
    sum(volume) AS volume
FROM market_data_ohlcv
WHERE timeframe = '1m'
GROUP BY time_bucket('1 hour', time), instrument_id;

-- Add refresh policy
SELECT add_continuous_aggregate_policy('market_data_ohlcv_1h',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');
```

---

## Common Anti-Patterns

### 1. N+1 Query Problem

**Bad:**
```sql
-- Query 1: Get all orders
SELECT * FROM orders WHERE account_id = 123;

-- Then for each order (N queries):
SELECT * FROM trades WHERE order_id = ?;
```

**Good:**
```sql
-- Single query with JOIN
SELECT o.*, t.*
FROM orders o
LEFT JOIN trades t ON o.order_id = t.order_id
WHERE o.account_id = 123;
```

### 2. Large IN Clauses

**Bad:**
```sql
SELECT * FROM instruments 
WHERE instrument_id IN (1, 2, 3, ... 1000);  -- 1000 IDs
```

**Good:**
```sql
-- Use temporary table or VALUES
WITH ids AS (
    SELECT * FROM unnest(ARRAY[1, 2, 3, ...]) AS instrument_id
)
SELECT i.* FROM instruments i
JOIN ids ON i.instrument_id = ids.instrument_id;
```

### 3. Correlated Subqueries

**Bad:**
```sql
SELECT *
FROM orders o
WHERE quantity > (
    SELECT AVG(quantity) 
    FROM orders o2 
    WHERE o2.account_id = o.account_id
);
```

**Good:**
```sql
WITH avg_quantities AS (
    SELECT account_id, AVG(quantity) as avg_quantity
    FROM orders
    GROUP BY account_id
)
SELECT o.*
FROM orders o
JOIN avg_quantities aq ON o.account_id = aq.account_id
WHERE o.quantity > aq.avg_quantity;
```

---

## Maintenance Best Practices

### 1. Regular VACUUM and ANALYZE

```sql
-- Analyze statistics
ANALYZE orders;
ANALYZE trades;
ANALYZE positions;

-- Manual vacuum if needed
VACUUM ANALYZE orders;
```

### 2. Monitor Query Performance

```sql
-- Enable pg_stat_statements
CREATE EXTENSION pg_stat_statements;

-- View slow queries
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    max_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 20;
```

### 3. Update Statistics

```sql
-- Increase statistics target for frequently filtered columns
ALTER TABLE orders ALTER COLUMN created_at SET STATISTICS 1000;
ALTER TABLE trades ALTER COLUMN executed_at SET STATISTICS 1000;
```

---

## Performance Monitoring

### Key Metrics to Watch

1. **Query Execution Time**: < 100ms for most queries
2. **Cache Hit Ratio**: > 95%
3. **Index Usage**: All frequently used indexes should have high scan counts
4. **Table Bloat**: Keep under 20%
5. **Connection Pool**: Monitor active/idle connections

### Monitoring Queries

```sql
-- Cache hit ratio
SELECT 
    sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) * 100 as cache_hit_ratio
FROM pg_statio_user_tables;

-- Index usage
SELECT 
    schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

-- Table sizes
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

---

## Scaling Strategies

### Vertical Scaling
- Increase memory for larger cache
- Add CPU cores for parallel queries
- Use faster storage (SSD/NVMe)

### Horizontal Scaling
- Read replicas for reporting queries
- Partitioning for large tables
- TimescaleDB for time-series data

### Query Optimization Checklist

- [ ] Add appropriate indexes
- [ ] Avoid SELECT *
- [ ] Use LIMIT for large result sets
- [ ] Optimize JOIN order
- [ ] Use window functions over subqueries
- [ ] Enable compression for time-series data
- [ ] Set up continuous aggregates
- [ ] Regular VACUUM and ANALYZE
- [ ] Monitor slow queries
- [ ] Update statistics for high-cardinality columns

---

For more information, refer to:
- [PostgreSQL Performance Tuning](https://www.postgresql.org/docs/current/performance-tips.html)
- [TimescaleDB Best Practices](https://docs.timescale.com/timescaledb/latest/how-to-guides/query-data/)
