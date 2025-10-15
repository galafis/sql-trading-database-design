-- ============================================================================
-- Database Monitoring Queries
-- Author: Gabriel Demetrios Lafis
-- Description: Queries for monitoring database health and performance
-- ============================================================================

-- ============================================================================
-- Query: Database Size and Growth
-- ============================================================================
SELECT 
    pg_database.datname AS database_name,
    pg_size_pretty(pg_database_size(pg_database.datname)) AS size,
    pg_database_size(pg_database.datname) AS bytes
FROM pg_database
WHERE datname = current_database();

-- ============================================================================
-- Query: Table Sizes
-- ============================================================================
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - 
                   pg_relation_size(schemaname||'.'||tablename)) AS index_size,
    pg_total_relation_size(schemaname||'.'||tablename) AS bytes
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- ============================================================================
-- Query: Table Row Counts
-- ============================================================================
SELECT 
    schemaname,
    tablename,
    n_live_tup AS row_count,
    n_dead_tup AS dead_rows,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_live_tup DESC;

-- ============================================================================
-- Query: Index Usage Statistics
-- ============================================================================
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

-- ============================================================================
-- Query: Unused Indexes
-- ============================================================================
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS scans
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
    AND idx_scan = 0
    AND indexrelname NOT LIKE '%_pkey'
ORDER BY pg_relation_size(indexrelid) DESC;

-- ============================================================================
-- Query: Cache Hit Ratio
-- ============================================================================
SELECT 
    'Index Hit Rate' AS metric,
    CASE 
        WHEN (sum(idx_blks_hit) + sum(idx_blks_read)) = 0 THEN 100
        ELSE (sum(idx_blks_hit) / (sum(idx_blks_hit) + sum(idx_blks_read))::numeric * 100)::numeric(5,2)
    END AS hit_rate
FROM pg_statio_user_indexes
UNION ALL
SELECT 
    'Table Hit Rate' AS metric,
    CASE 
        WHEN (sum(heap_blks_hit) + sum(heap_blks_read)) = 0 THEN 100
        ELSE (sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read))::numeric * 100)::numeric(5,2)
    END AS hit_rate
FROM pg_statio_user_tables;

-- ============================================================================
-- Query: Active Queries
-- ============================================================================
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query_start,
    EXTRACT(EPOCH FROM (now() - query_start)) AS query_duration_seconds,
    LEFT(query, 100) AS query_preview
FROM pg_stat_activity
WHERE datname = current_database()
    AND state != 'idle'
    AND pid != pg_backend_pid()
ORDER BY query_start;

-- ============================================================================
-- Query: Long Running Queries
-- ============================================================================
SELECT 
    pid,
    usename,
    application_name,
    state,
    query_start,
    EXTRACT(EPOCH FROM (now() - query_start)) AS duration_seconds,
    query
FROM pg_stat_activity
WHERE datname = current_database()
    AND state = 'active'
    AND query_start < now() - INTERVAL '1 minute'
ORDER BY query_start;

-- ============================================================================
-- Query: Blocking Queries
-- ============================================================================
SELECT 
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_statement,
    blocking_activity.query AS blocking_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

-- ============================================================================
-- Query: Connection Statistics
-- ============================================================================
SELECT 
    datname,
    COUNT(*) AS connections,
    COUNT(*) FILTER (WHERE state = 'active') AS active,
    COUNT(*) FILTER (WHERE state = 'idle') AS idle,
    COUNT(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction
FROM pg_stat_activity
GROUP BY datname
ORDER BY connections DESC;

-- ============================================================================
-- Query: Vacuum and Analyze Status
-- ============================================================================
SELECT 
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    vacuum_count,
    autovacuum_count,
    analyze_count,
    autoanalyze_count
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY last_autovacuum NULLS FIRST;

-- ============================================================================
-- Query: Deadlocks and Conflicts
-- ============================================================================
SELECT 
    datname,
    deadlocks,
    conflicts,
    temp_files,
    temp_bytes
FROM pg_stat_database
WHERE datname = current_database();

-- ============================================================================
-- Query: Recent Audit Log Entries
-- ============================================================================
SELECT 
    log_id,
    table_name,
    operation_type,
    description,
    changed_by,
    changed_at,
    severity
FROM audit_log
WHERE changed_at >= NOW() - INTERVAL '1 hour'
ORDER BY changed_at DESC
LIMIT 100;

-- ============================================================================
-- Query: System Health Check
-- ============================================================================
SELECT 
    'Database Connections' AS metric,
    COUNT(*)::text AS value,
    'connections' AS unit
FROM pg_stat_activity
WHERE datname = current_database()
UNION ALL
SELECT 
    'Active Queries' AS metric,
    COUNT(*)::text AS value,
    'queries' AS unit
FROM pg_stat_activity
WHERE datname = current_database() AND state = 'active'
UNION ALL
SELECT 
    'Database Size' AS metric,
    pg_size_pretty(pg_database_size(current_database())) AS value,
    'bytes' AS unit
UNION ALL
SELECT 
    'Cache Hit Ratio' AS metric,
    ROUND((sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0)) * 100, 2)::text || '%' AS value,
    'percent' AS unit
FROM pg_statio_user_tables;
