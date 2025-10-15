# Database Monitoring

## Overview

This guide covers monitoring strategies and tools for maintaining optimal database performance and health.

---

## Key Performance Indicators (KPIs)

### Database Health Metrics

| Metric | Target | Alert Threshold | Critical Threshold |
|--------|--------|-----------------|-------------------|
| CPU Usage | < 70% | > 80% | > 90% |
| Memory Usage | < 80% | > 85% | > 95% |
| Disk Usage | < 70% | > 80% | > 90% |
| Cache Hit Ratio | > 95% | < 90% | < 85% |
| Connection Count | < 80% max | > 85% max | > 95% max |
| Query Duration (p95) | < 100ms | > 500ms | > 1000ms |
| Replication Lag | < 1s | > 5s | > 30s |
| Deadlocks | 0 | > 1/hour | > 5/hour |

---

## Monitoring Setup

### 1. Enable pg_stat_statements

```sql
-- Add to postgresql.conf
shared_preload_libraries = 'pg_stat_statements, timescaledb'
pg_stat_statements.track = all
pg_stat_statements.max = 10000

-- Create extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### 2. Configure Logging

```sql
-- postgresql.conf
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 1GB
log_min_duration_statement = 100  -- Log queries > 100ms
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_statement = 'ddl'
log_temp_files = 0
```

---

## Monitoring Queries

### System Performance

```sql
-- Current database size
SELECT 
    pg_database.datname,
    pg_size_pretty(pg_database_size(pg_database.datname)) AS size
FROM pg_database
WHERE datname = current_database();

-- Table bloat check
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    n_dead_tup,
    n_live_tup,
    ROUND((n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0)), 2) AS dead_pct
FROM pg_stat_user_tables
WHERE n_live_tup > 0
ORDER BY n_dead_tup DESC;

-- Index bloat
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

### Query Performance

```sql
-- Top 20 slowest queries
SELECT 
    query,
    calls,
    ROUND(total_exec_time::numeric, 2) AS total_time_ms,
    ROUND(mean_exec_time::numeric, 2) AS mean_time_ms,
    ROUND(max_exec_time::numeric, 2) AS max_time_ms,
    ROUND(stddev_exec_time::numeric, 2) AS stddev_time_ms,
    rows
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Most frequently executed queries
SELECT 
    LEFT(query, 100) AS query_preview,
    calls,
    ROUND(total_exec_time::numeric / calls, 2) AS avg_time_ms
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 20;

-- Queries with highest total time
SELECT 
    LEFT(query, 100) AS query_preview,
    calls,
    ROUND(total_exec_time::numeric, 2) AS total_time_ms,
    ROUND((100 * total_exec_time / SUM(total_exec_time) OVER ())::numeric, 2) AS pct_total_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

### Connection Monitoring

```sql
-- Active connections by state
SELECT 
    state,
    COUNT(*) AS count,
    MAX(EXTRACT(EPOCH FROM (NOW() - query_start))) AS max_duration_seconds
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY state;

-- Long-running queries
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    state,
    EXTRACT(EPOCH FROM (NOW() - query_start)) AS duration_seconds,
    LEFT(query, 200) AS query
FROM pg_stat_activity
WHERE datname = current_database()
    AND state != 'idle'
    AND query_start < NOW() - INTERVAL '1 minute'
ORDER BY query_start;

-- Idle in transaction
SELECT 
    pid,
    usename,
    state,
    EXTRACT(EPOCH FROM (NOW() - state_change)) AS idle_seconds,
    query
FROM pg_stat_activity
WHERE state LIKE '%idle in transaction%'
ORDER BY state_change;
```

### Lock Monitoring

```sql
-- Current locks
SELECT 
    l.mode,
    l.locktype,
    l.relation::regclass,
    l.pid,
    a.usename,
    a.query,
    a.state
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE NOT l.granted
ORDER BY l.relation;

-- Lock wait times
SELECT 
    pid,
    usename,
    pg_blocking_pids(pid) AS blocked_by,
    query AS waiting_query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

---

## Prometheus Integration

### Setup PostgreSQL Exporter

```bash
# Install postgres_exporter
wget https://github.com/prometheus-community/postgres_exporter/releases/download/v0.11.1/postgres_exporter-0.11.1.linux-amd64.tar.gz
tar xvzf postgres_exporter-0.11.1.linux-amd64.tar.gz
cd postgres_exporter-0.11.1.linux-amd64

# Create connection string
export DATA_SOURCE_NAME="postgresql://monitoring_user:password@localhost/trading_db?sslmode=disable"

# Run exporter
./postgres_exporter
```

### Example Queries

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'postgresql'
    static_configs:
      - targets: ['localhost:9187']
```

### Key Metrics to Monitor

```promql
# Database size growth
rate(pg_database_size_bytes[1h])

# Connection count
pg_stat_database_numbackends

# Transaction rate
rate(pg_stat_database_xact_commit[1m])

# Cache hit ratio
pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read)

# Deadlocks
rate(pg_stat_database_deadlocks[5m])
```

---

## Grafana Dashboards

### Essential Panels

1. **Database Overview**
   - Database size
   - Active connections
   - Transaction rate
   - Cache hit ratio

2. **Query Performance**
   - Slow queries
   - Query duration (p50, p95, p99)
   - Queries per second

3. **Resource Usage**
   - CPU usage
   - Memory usage
   - Disk I/O
   - Network throughput

4. **Table Statistics**
   - Table sizes
   - Row counts
   - Dead tuples
   - Vacuum/analyze status

5. **Replication (if applicable)**
   - Replication lag
   - WAL generation rate
   - Streaming status

---

## Alerting Rules

### Critical Alerts

```yaml
# Prometheus alerting rules
groups:
  - name: postgresql_alerts
    rules:
      - alert: PostgreSQLDown
        expr: pg_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL is down"

      - alert: HighCPUUsage
        expr: process_cpu_seconds_total > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"

      - alert: LowCacheHitRatio
        expr: |
          pg_stat_database_blks_hit / 
          (pg_stat_database_blks_hit + pg_stat_database_blks_read) < 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Cache hit ratio below 85%"

      - alert: TooManyConnections
        expr: pg_stat_database_numbackends > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Too many database connections"

      - alert: DeadlocksDetected
        expr: rate(pg_stat_database_deadlocks[5m]) > 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Deadlocks detected"

      - alert: SlowQueries
        expr: |
          pg_stat_statements_mean_exec_time_seconds > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Slow queries detected"
```

---

## Application Monitoring

### Trading System Metrics

```sql
-- Create monitoring views
CREATE VIEW v_trading_metrics AS
SELECT 
    'orders_per_minute' AS metric,
    COUNT(*)::text AS value,
    'orders' AS unit
FROM orders
WHERE created_at >= NOW() - INTERVAL '1 minute'
UNION ALL
SELECT 
    'trades_per_minute' AS metric,
    COUNT(*)::text AS value,
    'trades' AS unit
FROM trades
WHERE executed_at >= NOW() - INTERVAL '1 minute'
UNION ALL
SELECT 
    'avg_order_fill_time' AS metric,
    ROUND(AVG(EXTRACT(EPOCH FROM (filled_at - created_at)))::numeric, 2)::text AS value,
    'seconds' AS unit
FROM orders
WHERE filled_at >= NOW() - INTERVAL '1 hour'
    AND filled_at IS NOT NULL
UNION ALL
SELECT 
    'failed_orders_rate' AS metric,
    ROUND((COUNT(*) FILTER (WHERE status = 'rejected')::numeric / 
           NULLIF(COUNT(*), 0)) * 100, 2)::text AS value,
    'percent' AS unit
FROM orders
WHERE created_at >= NOW() - INTERVAL '1 hour';

-- Query trading metrics
SELECT * FROM v_trading_metrics;
```

### Business Metrics

```sql
-- Daily trading volume
SELECT 
    DATE_TRUNC('day', executed_at) AS date,
    COUNT(*) AS trades,
    SUM(value) AS total_volume,
    COUNT(DISTINCT account_id) AS active_accounts
FROM trades
WHERE executed_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE_TRUNC('day', executed_at)
ORDER BY date DESC;

-- Position risk metrics
SELECT 
    COUNT(*) AS total_positions,
    SUM(unrealized_pnl) AS total_unrealized_pnl,
    AVG(unrealized_pnl) AS avg_position_pnl,
    MAX(quantity * current_price) AS largest_position_value
FROM positions;

-- Account health
SELECT 
    COUNT(*) FILTER (WHERE balance > 0) AS accounts_with_balance,
    COUNT(*) FILTER (WHERE balance < margin_used) AS margin_call_accounts,
    AVG(balance) AS avg_balance
FROM accounts
WHERE is_active = true;
```

---

## Health Check Endpoint

### Simple Health Check

```sql
-- Create health check function
CREATE OR REPLACE FUNCTION health_check()
RETURNS JSON AS $$
DECLARE
    result JSON;
BEGIN
    SELECT json_build_object(
        'status', 'healthy',
        'timestamp', NOW(),
        'database_size', pg_size_pretty(pg_database_size(current_database())),
        'active_connections', (SELECT COUNT(*) FROM pg_stat_activity WHERE datname = current_database()),
        'cache_hit_ratio', ROUND((
            SELECT sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0)
            FROM pg_statio_user_tables
        ) * 100, 2)
    ) INTO result;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Use in application
SELECT health_check();
```

---

## Maintenance Monitoring

### Vacuum Progress

```sql
-- Monitor vacuum progress
SELECT 
    p.pid,
    p.datname,
    p.relid::regclass AS table_name,
    p.phase,
    p.heap_blks_total,
    p.heap_blks_scanned,
    p.heap_blks_vacuumed,
    ROUND((p.heap_blks_scanned::numeric / NULLIF(p.heap_blks_total, 0)) * 100, 2) AS pct_complete
FROM pg_stat_progress_vacuum p;
```

### Auto-vacuum Status

```sql
-- Check auto-vacuum configuration
SELECT 
    name,
    setting,
    unit,
    short_desc
FROM pg_settings
WHERE name LIKE '%autovacuum%'
ORDER BY name;

-- Tables that need vacuum
SELECT 
    schemaname,
    tablename,
    n_dead_tup,
    n_live_tup,
    ROUND((n_dead_tup * 100.0 / NULLIF(n_live_tup, 0)), 2) AS dead_pct,
    last_autovacuum,
    last_vacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

---

## TimescaleDB Monitoring

### Chunk Status

```sql
-- Monitor chunk sizes
SELECT 
    hypertable_name,
    chunk_name,
    pg_size_pretty(total_bytes) AS size,
    range_start,
    range_end
FROM timescaledb_information.chunks
ORDER BY total_bytes DESC
LIMIT 20;

-- Compression stats
SELECT 
    hypertable_name,
    pg_size_pretty(before_compression_total_bytes) AS before_compression,
    pg_size_pretty(after_compression_total_bytes) AS after_compression,
    ROUND((1 - after_compression_total_bytes::numeric / before_compression_total_bytes) * 100, 2) AS compression_ratio_pct
FROM timescaledb_information.compression_settings;
```

---

## Monitoring Checklist

- [ ] pg_stat_statements enabled
- [ ] Prometheus exporter running
- [ ] Grafana dashboards configured
- [ ] Alert rules defined
- [ ] Log aggregation setup
- [ ] Backup monitoring active
- [ ] Query performance tracked
- [ ] Connection pooling monitored
- [ ] Replication lag checked (if applicable)
- [ ] Disk space monitored
- [ ] CPU/Memory alerts configured
- [ ] Application metrics exposed

---

For more information:
- [PostgreSQL Monitoring Documentation](https://www.postgresql.org/docs/current/monitoring.html)
- [TimescaleDB Monitoring](https://docs.timescale.com/timescaledb/latest/how-to-guides/monitoring/)
- [Prometheus PostgreSQL Exporter](https://github.com/prometheus-community/postgres_exporter)
