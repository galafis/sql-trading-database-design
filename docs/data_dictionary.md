# Data Dictionary

## Overview

This document provides comprehensive descriptions of all tables, columns, data types, and constraints in the Trading Database System.

---

## Core Tables

### users

User accounts and authentication information.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| user_id | BIGSERIAL | PRIMARY KEY | Unique user identifier |
| username | VARCHAR(50) | UNIQUE NOT NULL | Unique username for login |
| email | VARCHAR(255) | UNIQUE NOT NULL | User email address |
| password_hash | VARCHAR(255) | NOT NULL | Hashed password for authentication |
| first_name | VARCHAR(100) | | User's first name |
| last_name | VARCHAR(100) | | User's last name |
| phone | VARCHAR(20) | | Contact phone number |
| country_code | CHAR(2) | | ISO country code |
| kyc_status | VARCHAR(20) | DEFAULT 'pending' | KYC verification status (pending, approved, rejected) |
| is_active | BOOLEAN | DEFAULT true | Account active flag |
| created_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Account creation timestamp |
| updated_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Last update timestamp |
| last_login_at | TIMESTAMP WITH TIME ZONE | | Last login timestamp |

**Indexes:**
- `idx_users_email` on (email)
- `idx_users_username` on (username)
- `idx_users_kyc_status` on (kyc_status)

---

### accounts

Trading accounts associated with users.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| account_id | BIGSERIAL | PRIMARY KEY | Unique account identifier |
| user_id | BIGINT | FOREIGN KEY, NOT NULL | Reference to users table |
| account_number | VARCHAR(20) | UNIQUE NOT NULL | Unique account number |
| account_type | VARCHAR(20) | NOT NULL | Account type (cash, margin, demo) |
| currency | CHAR(3) | DEFAULT 'USD' | Account base currency |
| balance | DECIMAL(20, 8) | DEFAULT 0.00, CHECK >= 0 | Current account balance |
| available_balance | DECIMAL(20, 8) | DEFAULT 0.00, CHECK >= 0 | Available balance for trading |
| margin_used | DECIMAL(20, 8) | DEFAULT 0.00 | Margin currently in use |
| leverage | DECIMAL(5, 2) | DEFAULT 1.00, CHECK >= 1.00 | Account leverage multiplier |
| is_active | BOOLEAN | DEFAULT true | Account active status |
| created_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Account creation timestamp |
| updated_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Last update timestamp |

**Indexes:**
- `idx_accounts_user_id` on (user_id)
- `idx_accounts_account_number` on (account_number)

---

### instruments

Financial instruments available for trading.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| instrument_id | BIGSERIAL | PRIMARY KEY | Unique instrument identifier |
| symbol | VARCHAR(20) | UNIQUE NOT NULL | Trading symbol/ticker |
| instrument_name | VARCHAR(255) | NOT NULL | Full instrument name |
| instrument_type | VARCHAR(20) | NOT NULL | Type (stock, forex, crypto, futures, options) |
| exchange | VARCHAR(50) | | Exchange where traded |
| currency | CHAR(3) | DEFAULT 'USD' | Quote currency |
| is_tradeable | BOOLEAN | DEFAULT true | Whether currently tradeable |
| min_trade_size | DECIMAL(20, 8) | | Minimum order quantity |
| max_trade_size | DECIMAL(20, 8) | | Maximum order quantity |
| min_price | DECIMAL(20, 8) | | Minimum price increment |
| margin_requirement | DECIMAL(5, 4) | DEFAULT 1.0000 | Margin requirement percentage |
| volatility | DECIMAL(10, 6) | | Historical volatility measure |
| created_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Creation timestamp |
| updated_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Last update timestamp |

**Indexes:**
- `idx_instruments_symbol` on (symbol)
- `idx_instruments_type` on (instrument_type)

---

## Trading Tables

### orders

Order requests from clients.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| order_id | BIGSERIAL | PRIMARY KEY | Unique order identifier |
| account_id | BIGINT | FOREIGN KEY, NOT NULL | Reference to accounts |
| instrument_id | BIGINT | FOREIGN KEY, NOT NULL | Reference to instruments |
| order_type | VARCHAR(20) | NOT NULL | Order type (market, limit, stop, stop_limit) |
| side | VARCHAR(10) | NOT NULL | Buy or sell |
| quantity | DECIMAL(20, 8) | NOT NULL | Order quantity |
| filled_quantity | DECIMAL(20, 8) | DEFAULT 0.00 | Quantity filled |
| price | DECIMAL(20, 8) | | Limit price (for limit orders) |
| stop_price | DECIMAL(20, 8) | | Stop price (for stop orders) |
| average_fill_price | DECIMAL(20, 8) | | Average execution price |
| time_in_force | VARCHAR(10) | DEFAULT 'GTC' | Time in force (GTC, IOC, FOK, DAY) |
| status | VARCHAR(20) | DEFAULT 'pending' | Order status (pending, partial, filled, cancelled, rejected) |
| commission | DECIMAL(20, 8) | DEFAULT 0.00 | Trading commission |
| client_order_id | VARCHAR(50) | UNIQUE | Client-provided order ID |
| created_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Order creation time |
| updated_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Last update time |
| filled_at | TIMESTAMP WITH TIME ZONE | | Complete fill timestamp |
| cancelled_at | TIMESTAMP WITH TIME ZONE | | Cancellation timestamp |

**Indexes:**
- `idx_orders_account_id` on (account_id)
- `idx_orders_instrument_id` on (instrument_id)
- `idx_orders_status` on (status)
- `idx_orders_created_at` on (created_at DESC)

---

### trades

Executed trades.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| trade_id | BIGSERIAL | PRIMARY KEY | Unique trade identifier |
| order_id | BIGINT | FOREIGN KEY, NOT NULL | Reference to orders |
| account_id | BIGINT | FOREIGN KEY, NOT NULL | Reference to accounts |
| instrument_id | BIGINT | FOREIGN KEY, NOT NULL | Reference to instruments |
| side | VARCHAR(10) | NOT NULL | Buy or sell |
| quantity | DECIMAL(20, 8) | NOT NULL | Trade quantity |
| price | DECIMAL(20, 8) | NOT NULL | Execution price |
| value | DECIMAL(20, 8) | NOT NULL | Trade value (quantity × price) |
| commission | DECIMAL(20, 8) | DEFAULT 0.00 | Trading commission |
| trade_type | VARCHAR(20) | | Trade type (normal, short_cover, etc.) |
| settlement_status | VARCHAR(20) | | Settlement status (pending, settled) |
| settlement_date | TIMESTAMP WITH TIME ZONE | | Settlement timestamp |
| executed_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Execution timestamp |

**Indexes:**
- `idx_trades_order_id` on (order_id)
- `idx_trades_account_id` on (account_id)
- `idx_trades_instrument_id` on (instrument_id)
- `idx_trades_executed_at` on (executed_at DESC)

---

### positions

Open trading positions.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| position_id | BIGSERIAL | PRIMARY KEY | Unique position identifier |
| account_id | BIGINT | FOREIGN KEY, NOT NULL | Reference to accounts |
| instrument_id | BIGINT | FOREIGN KEY, NOT NULL | Reference to instruments |
| side | VARCHAR(10) | NOT NULL | Position side (long, short) |
| quantity | DECIMAL(20, 8) | NOT NULL | Position quantity |
| average_entry_price | DECIMAL(20, 8) | NOT NULL | Average entry price |
| current_price | DECIMAL(20, 8) | | Current market price |
| unrealized_pnl | DECIMAL(20, 8) | DEFAULT 0.00 | Unrealized profit/loss |
| realized_pnl | DECIMAL(20, 8) | DEFAULT 0.00 | Realized profit/loss |
| total_pnl | DECIMAL(20, 8) | DEFAULT 0.00 | Total P&L |
| margin_used | DECIMAL(20, 8) | DEFAULT 0.00 | Margin allocated to position |
| opened_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Position open timestamp |
| updated_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Last update timestamp |

**Indexes:**
- `idx_positions_account_id` on (account_id)
- `idx_positions_instrument_id` on (instrument_id)

---

### transactions

Financial transactions (deposits, withdrawals, etc.).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| transaction_id | BIGSERIAL | PRIMARY KEY | Unique transaction identifier |
| account_id | BIGINT | FOREIGN KEY, NOT NULL | Reference to accounts |
| transaction_type | VARCHAR(20) | NOT NULL | Type (deposit, withdrawal, dividend, fee) |
| amount | DECIMAL(20, 8) | NOT NULL | Transaction amount |
| currency | CHAR(3) | DEFAULT 'USD' | Transaction currency |
| status | VARCHAR(20) | DEFAULT 'pending' | Status (pending, completed, failed) |
| reference_id | VARCHAR(100) | | External reference ID |
| description | TEXT | | Transaction description |
| executed_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Execution timestamp |

**Indexes:**
- `idx_transactions_account_id` on (account_id)
- `idx_transactions_type` on (transaction_type)

---

## Audit and History Tables

### audit_log

Comprehensive audit trail of all database changes.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| log_id | BIGSERIAL | PRIMARY KEY | Unique log entry identifier |
| table_name | VARCHAR(100) | NOT NULL | Table that was modified |
| record_id | BIGINT | NOT NULL | ID of modified record |
| operation_type | VARCHAR(10) | NOT NULL | Operation (INSERT, UPDATE, DELETE) |
| old_data | JSON | | Previous record state |
| new_data | JSON | | New record state |
| description | TEXT | | Operation description |
| changed_by | VARCHAR(100) | | User who made the change |
| changed_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Change timestamp |
| severity | VARCHAR(20) | | Alert severity level |

**Indexes:**
- `idx_audit_log_table_name` on (table_name)
- `idx_audit_log_changed_at` on (changed_at DESC)

---

### position_history

Historical record of closed positions.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| history_id | BIGSERIAL | PRIMARY KEY | Unique history entry ID |
| position_id | BIGINT | | Original position ID |
| account_id | BIGINT | FOREIGN KEY, NOT NULL | Reference to accounts |
| instrument_id | BIGINT | FOREIGN KEY, NOT NULL | Reference to instruments |
| side | VARCHAR(10) | NOT NULL | Position side (long, short) |
| quantity | DECIMAL(20, 8) | NOT NULL | Position quantity |
| entry_price | DECIMAL(20, 8) | NOT NULL | Entry price |
| exit_price | DECIMAL(20, 8) | NOT NULL | Exit price |
| realized_pnl | DECIMAL(20, 8) | NOT NULL | Realized profit/loss |
| holding_period | INTERVAL | | Time position was held |
| opened_at | TIMESTAMP WITH TIME ZONE | | Position open timestamp |
| closed_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Position close timestamp |

**Indexes:**
- `idx_position_history_account_id` on (account_id)
- `idx_position_history_closed_at` on (closed_at DESC)

---

## Market Data Tables (TimescaleDB)

### market_data_ohlcv

OHLCV candlestick data (TimescaleDB hypertable).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| time | TIMESTAMP WITH TIME ZONE | NOT NULL | Candlestick timestamp |
| instrument_id | BIGINT | NOT NULL | Reference to instruments |
| timeframe | VARCHAR(10) | NOT NULL | Timeframe (1m, 5m, 15m, 1h, 1d) |
| open | DECIMAL(20, 8) | NOT NULL | Opening price |
| high | DECIMAL(20, 8) | NOT NULL | Highest price |
| low | DECIMAL(20, 8) | NOT NULL | Lowest price |
| close | DECIMAL(20, 8) | NOT NULL | Closing price |
| volume | DECIMAL(20, 8) | NOT NULL | Trading volume |

**Primary Key:** (time, instrument_id, timeframe)

---

### market_data_tickers

Real-time ticker data.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| ticker_id | BIGSERIAL | PRIMARY KEY | Unique ticker ID |
| instrument_id | BIGINT | FOREIGN KEY, NOT NULL | Reference to instruments |
| last_price | DECIMAL(20, 8) | NOT NULL | Last traded price |
| bid_price | DECIMAL(20, 8) | | Best bid price |
| ask_price | DECIMAL(20, 8) | | Best ask price |
| volume | DECIMAL(20, 8) | | 24h volume |
| change_24h | DECIMAL(20, 8) | | 24h price change |
| change_pct_24h | DECIMAL(10, 4) | | 24h percentage change |
| updated_at | TIMESTAMP WITH TIME ZONE | DEFAULT CURRENT_TIMESTAMP | Last update time |

---

## Data Type Reference

- **BIGSERIAL**: Auto-incrementing 8-byte integer
- **BIGINT**: 8-byte integer
- **DECIMAL(p, s)**: Exact numeric with precision p and scale s
- **VARCHAR(n)**: Variable-length string with max length n
- **CHAR(n)**: Fixed-length string of length n
- **TEXT**: Variable-length string with no limit
- **BOOLEAN**: True/false value
- **TIMESTAMP WITH TIME ZONE**: Date and time with timezone
- **INTERVAL**: Time interval
- **JSON**: JSON data

---

## Constraint Types

- **PRIMARY KEY**: Uniquely identifies each row
- **FOREIGN KEY**: Maintains referential integrity
- **UNIQUE**: Ensures column value uniqueness
- **NOT NULL**: Column must have a value
- **CHECK**: Validates column value constraints
- **DEFAULT**: Provides default value if none specified

---

## Naming Conventions

- **Tables**: Plural nouns (users, orders, trades)
- **Columns**: Snake_case (user_id, created_at)
- **Indexes**: idx_{table}_{column(s)} (idx_users_email)
- **Foreign Keys**: fk_{child_table}_{parent_table}
- **Primary Keys**: {table}_pkey (users_pkey)
- **Triggers**: {action}_{table} (audit_users)
- **Functions**: {verb}_{noun} (calculate_pnl)

---

This data dictionary should be updated whenever schema changes are made to the database.
