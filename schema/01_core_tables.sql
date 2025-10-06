-- ============================================================================
-- Core Tables for Trading System
-- Author: Gabriel Demetrios Lafis
-- Description: Core entities including users, accounts, and instruments
-- ============================================================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- Users Table
-- ============================================================================
CREATE TABLE users (
    user_id BIGSERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    phone VARCHAR(20),
    country_code CHAR(2),
    kyc_status VARCHAR(20) DEFAULT 'pending' CHECK (kyc_status IN ('pending', 'approved', 'rejected')),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_kyc_status ON users(kyc_status);

COMMENT ON TABLE users IS 'System users with authentication and KYC information';

-- ============================================================================
-- Accounts Table
-- ============================================================================
CREATE TABLE accounts (
    account_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    account_number VARCHAR(20) UNIQUE NOT NULL,
    account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('cash', 'margin', 'demo')),
    currency CHAR(3) DEFAULT 'USD',
    balance DECIMAL(20, 8) DEFAULT 0.00 CHECK (balance >= 0),
    available_balance DECIMAL(20, 8) DEFAULT 0.00 CHECK (available_balance >= 0),
    margin_used DECIMAL(20, 8) DEFAULT 0.00,
    leverage DECIMAL(5, 2) DEFAULT 1.00 CHECK (leverage >= 1.00),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_accounts_user_id ON accounts(user_id);
CREATE INDEX idx_accounts_account_number ON accounts(account_number);
CREATE INDEX idx_accounts_type ON accounts(account_type);

COMMENT ON TABLE accounts IS 'Trading accounts associated with users';

-- ============================================================================
-- Exchanges Table
-- ============================================================================
CREATE TABLE exchanges (
    exchange_id SERIAL PRIMARY KEY,
    exchange_code VARCHAR(10) UNIQUE NOT NULL,
    exchange_name VARCHAR(100) NOT NULL,
    country CHAR(2),
    timezone VARCHAR(50),
    trading_hours_start TIME,
    trading_hours_end TIME,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_exchanges_code ON exchanges(exchange_code);

COMMENT ON TABLE exchanges IS 'Financial exchanges where instruments are traded';

-- ============================================================================
-- Instruments Table
-- ============================================================================
CREATE TABLE instruments (
    instrument_id BIGSERIAL PRIMARY KEY,
    symbol VARCHAR(20) UNIQUE NOT NULL,
    instrument_name VARCHAR(255),
    instrument_type VARCHAR(20) NOT NULL CHECK (instrument_type IN ('stock', 'forex', 'crypto', 'futures', 'options', 'index')),
    exchange_id INTEGER REFERENCES exchanges(exchange_id),
    base_currency CHAR(3),
    quote_currency CHAR(3),
    contract_size DECIMAL(20, 8) DEFAULT 1.00,
    tick_size DECIMAL(20, 8) DEFAULT 0.01,
    min_quantity DECIMAL(20, 8) DEFAULT 0.01,
    max_quantity DECIMAL(20, 8),
    is_tradeable BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_instruments_symbol ON instruments(symbol);
CREATE INDEX idx_instruments_type ON instruments(instrument_type);
CREATE INDEX idx_instruments_exchange ON instruments(exchange_id);

COMMENT ON TABLE instruments IS 'Financial instruments available for trading';

-- ============================================================================
-- Instrument Metadata Table
-- ============================================================================
CREATE TABLE instrument_metadata (
    instrument_id BIGINT PRIMARY KEY REFERENCES instruments(instrument_id) ON DELETE CASCADE,
    sector VARCHAR(100),
    industry VARCHAR(100),
    market_cap BIGINT,
    description TEXT,
    website VARCHAR(255),
    metadata JSONB,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE instrument_metadata IS 'Additional metadata for instruments';

-- ============================================================================
-- Update Timestamp Trigger Function
-- ============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update triggers
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_accounts_updated_at
    BEFORE UPDATE ON accounts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_instruments_updated_at
    BEFORE UPDATE ON instruments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
