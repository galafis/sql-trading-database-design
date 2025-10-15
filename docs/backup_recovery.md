# Backup and Recovery

## Overview

This document outlines backup and recovery strategies for the trading database system to ensure data integrity and business continuity.

---

## Backup Strategy

### 1. Full Database Backups

**Daily Full Backups:**
```bash
#!/bin/bash
# daily_backup.sh

BACKUP_DIR="/backups/trading_db"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_NAME="trading_db"

# Create backup directory
mkdir -p $BACKUP_DIR

# Perform full backup with pg_dump
pg_dump -Fc -Z9 -f "$BACKUP_DIR/full_backup_$TIMESTAMP.dump" $DB_NAME

# Keep only last 7 days of backups
find $BACKUP_DIR -name "full_backup_*.dump" -mtime +7 -delete

echo "Backup completed: full_backup_$TIMESTAMP.dump"
```

**Scheduling with cron:**
```bash
# Run daily at 2 AM
0 2 * * * /path/to/daily_backup.sh >> /var/log/db_backup.log 2>&1
```

### 2. Incremental Backups (WAL Archiving)

**Configure PostgreSQL for WAL archiving:**

```sql
-- postgresql.conf
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /backups/wal_archive/%f && cp %p /backups/wal_archive/%f'
archive_timeout = 300  -- Archive every 5 minutes
max_wal_senders = 3
wal_keep_size = 1GB
```

**WAL Archive Script:**
```bash
#!/bin/bash
# archive_wal.sh

WAL_ARCHIVE="/backups/wal_archive"
S3_BUCKET="s3://my-trading-db-backups/wal"

# Create archive directory
mkdir -p $WAL_ARCHIVE

# Sync to S3 (optional)
aws s3 sync $WAL_ARCHIVE $S3_BUCKET --delete

# Keep only last 30 days locally
find $WAL_ARCHIVE -type f -mtime +30 -delete
```

### 3. Logical Backups (per table)

**Export specific tables:**
```bash
# Export critical tables
pg_dump -t users -t accounts -t orders -t trades -t positions \
    --format=custom --file=critical_tables_$(date +%Y%m%d).dump trading_db
```

---

## Backup Types Comparison

| Type | Frequency | Retention | Size | Recovery Time |
|------|-----------|-----------|------|---------------|
| Full | Daily | 7 days | Large | Fast |
| Incremental (WAL) | Continuous | 30 days | Small | Medium |
| Logical (tables) | Weekly | 30 days | Medium | Fast |
| Point-in-Time | Via WAL | 30 days | Small | Medium |

---

## Recovery Procedures

### 1. Full Database Recovery

**Restore from full backup:**
```bash
#!/bin/bash
# restore_full.sh

BACKUP_FILE="/backups/trading_db/full_backup_20241015_020000.dump"
DB_NAME="trading_db"

# Drop existing database (WARNING: data loss)
dropdb $DB_NAME

# Create new database
createdb $DB_NAME

# Enable extensions
psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS uuid-ossp;"
psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

# Restore from backup
pg_restore -d $DB_NAME $BACKUP_FILE

echo "Database restored successfully"
```

### 2. Point-in-Time Recovery (PITR)

**Restore to specific time:**
```bash
#!/bin/bash
# restore_pitr.sh

BASE_BACKUP="/backups/trading_db/full_backup_20241015_020000.dump"
WAL_ARCHIVE="/backups/wal_archive"
RECOVERY_TARGET="2024-10-15 14:30:00"

# Stop PostgreSQL
systemctl stop postgresql

# Restore base backup
pg_restore -d trading_db $BASE_BACKUP

# Create recovery configuration
cat > /var/lib/postgresql/data/recovery.conf << EOF
restore_command = 'cp $WAL_ARCHIVE/%f %p'
recovery_target_time = '$RECOVERY_TARGET'
recovery_target_action = 'promote'
EOF

# Start PostgreSQL (will enter recovery mode)
systemctl start postgresql

# Monitor recovery
tail -f /var/log/postgresql/postgresql.log
```

### 3. Table-Level Recovery

**Restore specific tables:**
```bash
# Restore only the orders table
pg_restore -d trading_db -t orders critical_tables_20241015.dump

# Or restore and rename to avoid conflicts
pg_restore -d trading_db -t orders --schema=recovery critical_tables_20241015.dump
```

---

## Disaster Recovery Plan

### Recovery Time Objective (RTO)

- **Critical Data (users, accounts, positions)**: < 1 hour
- **Historical Data (trades, market data)**: < 4 hours
- **Full System**: < 8 hours

### Recovery Point Objective (RPO)

- **Minimum Data Loss**: < 5 minutes (via WAL archiving)
- **Acceptable Data Loss**: < 1 hour

### DR Checklist

1. **Pre-Disaster:**
   - [ ] Automated daily backups configured
   - [ ] WAL archiving enabled
   - [ ] Backups tested monthly
   - [ ] Offsite backup storage configured
   - [ ] DR documentation up to date
   - [ ] Team trained on recovery procedures

2. **During Disaster:**
   - [ ] Assess extent of damage
   - [ ] Notify stakeholders
   - [ ] Begin recovery procedures
   - [ ] Document all actions taken

3. **Post-Recovery:**
   - [ ] Verify data integrity
   - [ ] Test application functionality
   - [ ] Update documentation
   - [ ] Conduct post-mortem
   - [ ] Improve DR plan

---

## Backup Verification

### Regular Backup Testing

**Monthly restore test:**
```bash
#!/bin/bash
# test_backup.sh

TEST_DB="trading_db_test"
LATEST_BACKUP=$(ls -t /backups/trading_db/full_backup_*.dump | head -1)

# Create test database
createdb $TEST_DB

# Restore backup
pg_restore -d $TEST_DB $LATEST_BACKUP

# Run validation queries
psql -d $TEST_DB << EOF
SELECT 'User count:' as check, COUNT(*) FROM users;
SELECT 'Account count:' as check, COUNT(*) FROM accounts;
SELECT 'Order count:' as check, COUNT(*) FROM orders;
SELECT 'Trade count:' as check, COUNT(*) FROM trades;
EOF

# Cleanup
dropdb $TEST_DB

echo "Backup verification completed"
```

### Data Integrity Checks

```sql
-- Check for orphaned records
SELECT 'Orphaned orders' as issue, COUNT(*) 
FROM orders o 
LEFT JOIN accounts a ON o.account_id = a.account_id 
WHERE a.account_id IS NULL;

-- Check for data consistency
SELECT 'Orders without trades' as issue, COUNT(*) 
FROM orders 
WHERE status = 'filled' 
AND order_id NOT IN (SELECT DISTINCT order_id FROM trades);

-- Check balance integrity
SELECT 'Balance mismatches' as issue, COUNT(*) 
FROM accounts 
WHERE available_balance > balance;
```

---

## Backup Storage

### Local Storage

**Requirements:**
- Separate physical drive from database
- RAID configuration for redundancy
- Regular disk health monitoring
- Sufficient capacity (30 days retention minimum)

### Cloud Storage

**S3 Backup Sync:**
```bash
#!/bin/bash
# sync_to_s3.sh

BACKUP_DIR="/backups/trading_db"
S3_BUCKET="s3://my-trading-db-backups"
AWS_REGION="us-east-1"

# Sync to S3 with encryption
aws s3 sync $BACKUP_DIR $S3_BUCKET \
    --region $AWS_REGION \
    --sse AES256 \
    --storage-class STANDARD_IA \
    --delete

echo "Backup synced to S3"
```

---

## TimescaleDB-Specific Backups

### Hypertable Backups

```bash
# Backup TimescaleDB hypertables
pg_dump -d trading_db \
    --format=custom \
    --compress=9 \
    --table=market_data_ohlcv \
    --table=market_data_quotes \
    --file=timescaledb_backup_$(date +%Y%m%d).dump
```

### Continuous Aggregates

```sql
-- Backup continuous aggregate definitions
SELECT 
    view_name,
    view_definition
FROM timescaledb_information.continuous_aggregates;

-- Export to file
\o /backups/continuous_aggregates.sql
SELECT view_definition 
FROM timescaledb_information.continuous_aggregates;
\o
```

---

## Security Considerations

### Backup Encryption

```bash
# Encrypt backups with GPG
pg_dump -Fc trading_db | gpg --encrypt --recipient backup@example.com \
    > encrypted_backup_$(date +%Y%m%d).dump.gpg

# Decrypt for restore
gpg --decrypt encrypted_backup_20241015.dump.gpg | pg_restore -d trading_db
```

### Access Control

```bash
# Set proper permissions
chmod 600 /backups/trading_db/*.dump
chown postgres:postgres /backups/trading_db/*.dump

# Restrict directory access
chmod 700 /backups/trading_db
```

---

## Monitoring and Alerts

### Backup Monitoring Script

```bash
#!/bin/bash
# monitor_backups.sh

BACKUP_DIR="/backups/trading_db"
MAX_AGE_HOURS=26  # Alert if last backup is > 26 hours old

LATEST_BACKUP=$(find $BACKUP_DIR -name "full_backup_*.dump" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")
BACKUP_AGE=$(( ($(date +%s) - $(stat -c %Y "$LATEST_BACKUP")) / 3600 ))

if [ $BACKUP_AGE -gt $MAX_AGE_HOURS ]; then
    echo "ALERT: Last backup is $BACKUP_AGE hours old"
    # Send alert (email, Slack, PagerDuty, etc.)
    exit 1
else
    echo "OK: Last backup is $BACKUP_AGE hours old"
    exit 0
fi
```

### Nagios/Prometheus Monitoring

```bash
# Add to cron for monitoring
*/15 * * * * /path/to/monitor_backups.sh || echo "Backup alert triggered"
```

---

## Recovery SLA

| Scenario | RTO | RPO | Priority |
|----------|-----|-----|----------|
| Single table corruption | 30 min | 5 min | P1 |
| Database corruption | 2 hours | 5 min | P0 |
| Server failure | 4 hours | 5 min | P0 |
| Data center failure | 8 hours | 1 hour | P0 |
| Accidental deletion | 1 hour | 5 min | P1 |

---

## Best Practices

1. **Test Regularly**: Perform restore tests monthly
2. **Automate**: Use scripts and cron jobs
3. **Monitor**: Set up alerts for backup failures
4. **Encrypt**: Protect sensitive data in backups
5. **Offsite**: Store copies in different locations
6. **Document**: Keep procedures up to date
7. **Verify**: Check backup integrity
8. **Rotate**: Follow retention policies

---

## Useful Commands

```bash
# List all backups
ls -lh /backups/trading_db/

# Check backup file size
du -h /backups/trading_db/full_backup_*.dump

# Verify backup contents (without restoring)
pg_restore --list full_backup_20241015.dump

# Estimate restore time
time pg_restore --jobs=4 -d test_db full_backup.dump

# Monitor restore progress
SELECT pid, query, state, query_start 
FROM pg_stat_activity 
WHERE datname = 'trading_db';
```

---

For additional information:
- [PostgreSQL Backup Documentation](https://www.postgresql.org/docs/current/backup.html)
- [TimescaleDB Backup Guide](https://docs.timescale.com/timescaledb/latest/how-to-guides/backup-and-restore/)
