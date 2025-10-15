# Database Migrations

## Overview

This directory contains database migration scripts for managing schema changes over time.

---

## Migration Strategy

We use Alembic for database migrations to:
- Track schema changes
- Enable version control of database structure
- Facilitate rollback capabilities
- Manage upgrades across environments

---

## Setup Alembic

### Install Alembic

```bash
pip install alembic psycopg2-binary
```

### Initialize Alembic

```bash
# Initialize alembic in the project
alembic init migrations/alembic

# Edit alembic.ini to point to your database
# sqlalchemy.url = postgresql://user:pass@localhost/trading_db
```

---

## Creating Migrations

### Auto-generate Migration

```bash
# Create a new migration
alembic revision --autogenerate -m "Add new column to orders table"

# Review the generated migration in migrations/alembic/versions/
```

### Manual Migration

```bash
# Create empty migration
alembic revision -m "Add custom index"

# Edit the file and add upgrade/downgrade logic
```

---

## Example Migration

```python
"""add_order_notes_column

Revision ID: 001
Revises: 
Create Date: 2024-10-15

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers
revision = '001'
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    # Add notes column to orders table
    op.add_column('orders', 
        sa.Column('notes', sa.Text(), nullable=True)
    )
    
    # Add index on notes for text search
    op.create_index(
        'idx_orders_notes', 
        'orders', 
        ['notes'], 
        postgresql_using='gin',
        postgresql_ops={'notes': 'gin_trgm_ops'}
    )

def downgrade():
    # Remove index
    op.drop_index('idx_orders_notes', table_name='orders')
    
    # Remove column
    op.drop_column('orders', 'notes')
```

---

## Running Migrations

### Upgrade to Latest

```bash
# Apply all pending migrations
alembic upgrade head
```

### Upgrade to Specific Version

```bash
# Upgrade to specific revision
alembic upgrade 001

# Upgrade one version
alembic upgrade +1
```

### Downgrade

```bash
# Downgrade one version
alembic downgrade -1

# Downgrade to specific revision
alembic downgrade 001

# Downgrade all
alembic downgrade base
```

### Check Status

```bash
# Show current revision
alembic current

# Show migration history
alembic history

# Show pending migrations
alembic heads
```

---

## Migration Best Practices

1. **Always test migrations** in development environment first
2. **Backup database** before running migrations in production
3. **Review generated migrations** - auto-generation isn't perfect
4. **Write both upgrade and downgrade** - enable rollback
5. **Keep migrations small** - easier to debug and rollback
6. **Test rollback** - ensure downgrade works
7. **Document breaking changes** - note any compatibility issues
8. **Use transactions** - wrap DDL in transactions when possible

---

## Migration Workflow

### Development

```bash
# 1. Make schema changes in code
# 2. Generate migration
alembic revision --autogenerate -m "description"

# 3. Review and edit generated migration
# 4. Test upgrade
alembic upgrade head

# 5. Test downgrade
alembic downgrade -1

# 6. Commit migration file
git add migrations/alembic/versions/xxx_description.py
git commit -m "Add migration: description"
```

### Production Deployment

```bash
# 1. Backup database
pg_dump -Fc trading_db > backup_$(date +%Y%m%d).dump

# 2. Run migrations
alembic upgrade head

# 3. Verify
psql -d trading_db -c "\d orders"  # Check schema

# 4. If issues, rollback
alembic downgrade -1
pg_restore -d trading_db backup_$(date +%Y%m%d).dump
```

---

## Common Migration Patterns

### Adding Column

```python
def upgrade():
    op.add_column('table_name', 
        sa.Column('new_column', sa.String(50), nullable=True)
    )

def downgrade():
    op.drop_column('table_name', 'new_column')
```

### Adding Index

```python
def upgrade():
    op.create_index('idx_table_column', 'table_name', ['column'])

def downgrade():
    op.drop_index('idx_table_column')
```

### Adding Foreign Key

```python
def upgrade():
    op.create_foreign_key(
        'fk_orders_accounts',
        'orders', 'accounts',
        ['account_id'], ['account_id']
    )

def downgrade():
    op.drop_constraint('fk_orders_accounts', 'orders')
```

### Renaming Column

```python
def upgrade():
    op.alter_column('table_name', 'old_name', new_column_name='new_name')

def downgrade():
    op.alter_column('table_name', 'new_name', new_column_name='old_name')
```

---

## Alternative: SQL-Based Migrations

For pure SQL migrations without Alembic:

```bash
# migrations/001_add_order_notes.sql
-- Upgrade
ALTER TABLE orders ADD COLUMN notes TEXT;
CREATE INDEX idx_orders_notes ON orders(notes);

-- migrations/001_add_order_notes_rollback.sql  
-- Downgrade
DROP INDEX idx_orders_notes;
ALTER TABLE orders DROP COLUMN notes;
```

Apply manually:
```bash
psql -d trading_db -f migrations/001_add_order_notes.sql
```

---

## Migration Tracking

Keep a migration log:

```
| Date | Version | Description | Applied By | Status |
|------|---------|-------------|------------|--------|
| 2024-10-15 | 001 | Add order notes | admin | Success |
| 2024-10-16 | 002 | Add position index | admin | Success |
```

---

## Resources

- [Alembic Documentation](https://alembic.sqlalchemy.org/)
- [PostgreSQL ALTER TABLE](https://www.postgresql.org/docs/current/sql-altertable.html)
- [Database Migration Best Practices](https://www.liquibase.com/blog/database-migration-best-practices)
