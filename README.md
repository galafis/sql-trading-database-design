# 🗄️ SQL Trading Database Design

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15%2B-blue.svg)](https://www.postgresql.org/)
[![TimescaleDB](https://img.shields.io/badge/TimescaleDB-2.11%2B-orange.svg)](https://www.timescale.com/)

[English](#english) | [Português](#português)

---

<a name="english"></a>

## 📖 Overview

A **comprehensive database design** for a trading system with optimized schema, stored procedures, triggers, and views. This project provides production-ready SQL code for PostgreSQL with TimescaleDB for time-series data.

### Key Features

- **📊 Complete Schema**: Users, accounts, instruments, orders, trades, positions
- **⏱️ Time-Series Data**: TimescaleDB hypertables for OHLCV and market data
- **🔧 Stored Procedures**: Order execution, position management, P&L calculations
- **🎯 Triggers**: Audit logging, data validation, cascade operations
- **📈 Views**: Portfolio aggregation, performance metrics, reporting
- **⚡ Performance Optimized**: Indexes, partitioning, continuous aggregates
- **🔒 Data Integrity**: Foreign keys, constraints, transaction isolation
- **📝 Well Documented**: Comprehensive comments and data dictionary

---

## 🏗️ Database Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Trading Database Schema                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │    Users     │   │   Accounts   │   │ Instruments  │        │
│  │              │──▶│              │   │              │        │
│  └──────────────┘   └──────┬───────┘   └──────┬───────┘        │
│                            │                   │                 │
│                            ▼                   ▼                 │
│                     ┌──────────────┐   ┌──────────────┐         │
│                     │    Orders    │──▶│    Trades    │         │
│                     └──────┬───────┘   └──────┬───────┘         │
│                            │                   │                 │
│                            ▼                   ▼                 │
│                     ┌──────────────┐   ┌──────────────┐         │
│                     │  Positions   │   │Transactions  │         │
│                     └──────────────┘   └──────────────┘         │
│                                                                   │
│  ┌──────────────────────────────────────────────────────┐       │
│  │         Market Data (TimescaleDB Hypertables)        │       │
│  ├──────────────────────────────────────────────────────┤       │
│  │  • OHLCV (Candlesticks)                              │       │
│  │  • Quotes (Bid/Ask)                                  │       │
│  │  • Tickers (Latest prices)                           │       │
│  │  • Trades (Tick data)                                │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Prerequisites

- **PostgreSQL 15+**
- **TimescaleDB 2.11+**
- **psql** command-line tool

### Installation

```bash
# Clone the repository
git clone https://github.com/gabriellafis/sql-trading-database-design.git
cd sql-trading-database-design

# Create database
createdb trading_db

# Enable TimescaleDB extension
psql -d trading_db -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"

# Run schema scripts
psql -d trading_db -f schema/01_core_tables.sql
psql -d trading_db -f schema/02_trading_tables.sql
psql -d trading_db -f schema/03_market_data.sql

# Create functions and procedures
psql -d trading_db -f functions/position_functions.sql
psql -d trading_db -f procedures/order_execution.sql

# Create views
psql -d trading_db -f views/portfolio_view.sql
```

---

## 📊 Database Schema

### Core Tables

#### Users
```sql
CREATE TABLE users (
    user_id BIGSERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    kyc_status VARCHAR(20) DEFAULT 'pending',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

#### Accounts
```sql
CREATE TABLE accounts (
    account_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id),
    account_number VARCHAR(20) UNIQUE NOT NULL,
    account_type VARCHAR(20) NOT NULL,
    balance DECIMAL(20, 8) DEFAULT 0.00,
    available_balance DECIMAL(20, 8) DEFAULT 0.00,
    leverage DECIMAL(5, 2) DEFAULT 1.00
);
```

#### Instruments
```sql
CREATE TABLE instruments (
    instrument_id BIGSERIAL PRIMARY KEY,
    symbol VARCHAR(20) UNIQUE NOT NULL,
    instrument_type VARCHAR(20) NOT NULL,
    exchange_id INTEGER REFERENCES exchanges(exchange_id),
    is_tradeable BOOLEAN DEFAULT true
);
```

### Trading Tables

#### Orders
```sql
CREATE TABLE orders (
    order_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id),
    instrument_id BIGINT NOT NULL REFERENCES instruments(instrument_id),
    order_type VARCHAR(20) NOT NULL,
    side VARCHAR(10) NOT NULL,
    quantity DECIMAL(20, 8) NOT NULL,
    price DECIMAL(20, 8),
    status VARCHAR(20) DEFAULT 'pending'
);
```

#### Trades
```sql
CREATE TABLE trades (
    trade_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES orders(order_id),
    account_id BIGINT NOT NULL REFERENCES accounts(account_id),
    instrument_id BIGINT NOT NULL REFERENCES instruments(instrument_id),
    quantity DECIMAL(20, 8) NOT NULL,
    price DECIMAL(20, 8) NOT NULL,
    executed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

#### Positions
```sql
CREATE TABLE positions (
    position_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id),
    instrument_id BIGINT NOT NULL REFERENCES instruments(instrument_id),
    side VARCHAR(10) NOT NULL,
    quantity DECIMAL(20, 8) NOT NULL,
    average_entry_price DECIMAL(20, 8) NOT NULL,
    unrealized_pnl DECIMAL(20, 8) DEFAULT 0.00
);
```

### Market Data Tables (TimescaleDB)

#### OHLCV Data
```sql
CREATE TABLE market_data_ohlcv (
    time TIMESTAMP WITH TIME ZONE NOT NULL,
    instrument_id BIGINT NOT NULL,
    timeframe VARCHAR(10) NOT NULL,
    open DECIMAL(20, 8) NOT NULL,
    high DECIMAL(20, 8) NOT NULL,
    low DECIMAL(20, 8) NOT NULL,
    close DECIMAL(20, 8) NOT NULL,
    volume DECIMAL(20, 8) NOT NULL,
    PRIMARY KEY (time, instrument_id, timeframe)
);

SELECT create_hypertable('market_data_ohlcv', 'time');
```

---

## 🔧 Stored Procedures

### Place Order
```sql
SELECT place_order(
    p_account_id := 1,
    p_instrument_id := 100,
    p_order_type := 'limit',
    p_side := 'buy',
    p_quantity := 10.0,
    p_price := 150.50
);
```

### Execute Trade
```sql
SELECT execute_trade(
    p_order_id := 12345,
    p_quantity := 10.0,
    p_price := 150.50
);
```

### Cancel Order
```sql
SELECT cancel_order(
    p_order_id := 12345,
    p_reason := 'User requested cancellation'
);
```

---

## 📈 Views and Reporting

### Portfolio Summary
```sql
SELECT * FROM v_portfolio_summary WHERE account_id = 1;
```

**Returns:**
- Cash balance
- Positions value
- Total equity
- Unrealized P&L
- Realized P&L
- Open positions count

### Position Details
```sql
SELECT * FROM v_position_details WHERE account_id = 1;
```

**Returns:**
- Position details
- Current P&L
- P&L percentage
- Holding time
- Position value

### Performance Metrics
```sql
SELECT * FROM v_performance_metrics WHERE account_id = 1;
```

**Returns:**
- Total trades
- Win rate
- Profit factor
- Average P&L
- Best/worst trades

---

## ⚡ Performance Optimization

### Indexes
```sql
-- Order indexes for fast lookups
CREATE INDEX idx_orders_account_id ON orders(account_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);

-- Position indexes
CREATE INDEX idx_positions_account_id ON positions(account_id);
CREATE INDEX idx_positions_instrument_id ON positions(instrument_id);
```

### TimescaleDB Features

**Compression** (reduce storage by 90%+):
```sql
ALTER TABLE market_data_ohlcv SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'instrument_id,timeframe'
);

SELECT add_compression_policy('market_data_ohlcv', INTERVAL '7 days');
```

**Continuous Aggregates** (pre-computed aggregations):
```sql
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
```

**Retention Policies** (automatic data cleanup):
```sql
SELECT add_retention_policy('market_data_ohlcv', INTERVAL '2 years');
```

---

## 📁 Project Structure

```
sql-trading-database-design/
├── schema/
│   ├── 01_core_tables.sql          # Users, accounts, instruments
│   ├── 02_trading_tables.sql       # Orders, trades, positions
│   └── 03_market_data.sql          # OHLCV, quotes, tickers
├── functions/
│   ├── position_functions.sql      # Position management
│   └── pnl_functions.sql           # P&L calculations
├── procedures/
│   ├── order_execution.sql         # Order placement & execution
│   └── settlement.sql              # Settlement procedures
├── triggers/
│   ├── audit_triggers.sql          # Audit logging
│   └── validation_triggers.sql     # Data validation
├── views/
│   ├── portfolio_view.sql          # Portfolio aggregation
│   ├── risk_view.sql               # Risk metrics
│   └── pnl_view.sql                # P&L reporting
├── queries/
│   ├── analytics/                  # Analytical queries
│   ├── reports/                    # Report queries
│   └── monitoring/                 # Monitoring queries
├── migrations/
│   └── alembic/                    # Database migrations
├── tests/
│   ├── unit/                       # Unit tests
│   └── performance/                # Performance tests
├── docs/
│   ├── erd.png                     # Entity-relationship diagram
│   └── data_dictionary.md          # Data dictionary
└── README.md                       # This file
```

---

## 🛠️ Technology Stack

| Component | Technology |
|-----------|-----------|
| Database | PostgreSQL 15+ |
| Time-Series | TimescaleDB 2.11+ |
| Language | SQL (PL/pgSQL) |
| Migrations | Alembic |
| Testing | pgTAP |

---

## 📊 Entity Relationship Diagram

```
users ──┐
        │
        ├──▶ accounts ──┐
        │               │
        │               ├──▶ orders ──▶ trades
        │               │
        │               └──▶ positions
        │
exchanges ──▶ instruments ──┐
                            │
                            ├──▶ orders
                            ├──▶ trades
                            ├──▶ positions
                            └──▶ market_data_*
```

---

## 🧪 Testing

### Run Unit Tests
```bash
pg_prove tests/unit/*.sql
```

### Performance Testing
```bash
psql -d trading_db -f tests/performance/benchmark_orders.sql
```

### Load Testing
```bash
pgbench -c 10 -j 2 -t 1000 -f tests/load/place_orders.sql trading_db
```

---

## 📚 Documentation

- **[Data Dictionary](docs/data_dictionary.md)**: Complete field descriptions
- **[Query Optimization Guide](docs/query_optimization.md)**: Performance tips
- **[Backup & Recovery](docs/backup_recovery.md)**: Backup strategies
- **[Monitoring](docs/monitoring.md)**: Database monitoring setup

---

## 🔒 Security Best Practices

1. **Use parameterized queries** to prevent SQL injection
2. **Encrypt sensitive data** (passwords, personal information)
3. **Implement row-level security** for multi-tenant scenarios
4. **Regular backups** with point-in-time recovery
5. **Audit logging** for all critical operations
6. **Least privilege** database user permissions

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👤 Author

**Gabriel Demetrios Lafis**

- GitHub: [@gabriellafis](https://github.com/gabriellafis)
- LinkedIn: [Gabriel Demetrios Lafis](https://linkedin.com/in/gabriel-lafis)

---

<a name="português"></a>

## 📖 Visão Geral

Um **design completo de banco de dados** para sistema de trading com schema otimizado, stored procedures, triggers e views. Este projeto fornece código SQL pronto para produção para PostgreSQL com TimescaleDB para dados de séries temporais.

### Principais Recursos

- **📊 Schema Completo**: Usuários, contas, instrumentos, ordens, trades, posições
- **⏱️ Dados de Séries Temporais**: Hypertables TimescaleDB para OHLCV e dados de mercado
- **🔧 Stored Procedures**: Execução de ordens, gestão de posições, cálculos de P&L
- **🎯 Triggers**: Audit logging, validação de dados, operações em cascata
- **📈 Views**: Agregação de portfólio, métricas de performance, relatórios
- **⚡ Otimizado para Performance**: Indexes, particionamento, agregações contínuas
- **🔒 Integridade de Dados**: Foreign keys, constraints, isolamento transacional
- **📝 Bem Documentado**: Comentários abrangentes e dicionário de dados

---

## 🚀 Início Rápido

### Pré-requisitos

- **PostgreSQL 15+**
- **TimescaleDB 2.11+**
- **psql** command-line tool

### Instalação

```bash
# Clone o repositório
git clone https://github.com/gabriellafis/sql-trading-database-design.git
cd sql-trading-database-design

# Crie o banco de dados
createdb trading_db

# Habilite a extensão TimescaleDB
psql -d trading_db -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"

# Execute os scripts de schema
psql -d trading_db -f schema/01_core_tables.sql
psql -d trading_db -f schema/02_trading_tables.sql
psql -d trading_db -f schema/03_market_data.sql

# Crie functions e procedures
psql -d trading_db -f functions/position_functions.sql
psql -d trading_db -f procedures/order_execution.sql

# Crie views
psql -d trading_db -f views/portfolio_view.sql
```

---

## 📄 Licença

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

---

## 👤 Autor

**Gabriel Demetrios Lafis**

- GitHub: [@gabriellafis](https://github.com/gabriellafis)
- LinkedIn: [Gabriel Demetrios Lafis](https://linkedin.com/in/gabriel-lafis)

---

## ⭐ Mostre seu apoio

Se este projeto foi útil para você, considere dar uma ⭐️!
