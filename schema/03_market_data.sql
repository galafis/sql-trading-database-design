-- ============================================================================
-- Market Data Tables for Trading System
-- Author: Gabriel Demetrios Lafis
-- Description: OHLCV data, quotes, and tickers using TimescaleDB
-- ============================================================================

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- ============================================================================
-- Market Data OHLCV Table (TimescaleDB Hypertable)
-- ============================================================================
CREATE TABLE market_data_ohlcv (
    time TIMESTAMP WITH TIME ZONE NOT NULL,
    instrument_id BIGINT NOT NULL REFERENCES instruments(instrument_id),
    timeframe VARCHAR(10) NOT NULL CHECK (timeframe IN ('1m', '5m', '15m', '30m', '1h', '4h', '1d', '1w', '1M')),
    open DECIMAL(20, 8) NOT NULL,
    high DECIMAL(20, 8) NOT NULL,
    low DECIMAL(20, 8) NOT NULL,
    close DECIMAL(20, 8) NOT NULL,
    volume DECIMAL(20, 8) NOT NULL,
    quote_volume DECIMAL(20, 8),
    trades_count INTEGER,
    PRIMARY KEY (time, instrument_id, timeframe)
);

-- Convert to hypertable
SELECT create_hypertable('market_data_ohlcv', 'time');

-- Create indexes
CREATE INDEX idx_market_data_instrument_time ON market_data_ohlcv (instrument_id, time DESC);
CREATE INDEX idx_market_data_timeframe ON market_data_ohlcv (timeframe, time DESC);

-- Add compression policy (compress data older than 7 days)
ALTER TABLE market_data_ohlcv SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'instrument_id,timeframe'
);

SELECT add_compression_policy('market_data_ohlcv', INTERVAL '7 days');

-- Add retention policy (keep data for 2 years)
SELECT add_retention_policy('market_data_ohlcv', INTERVAL '2 years');

COMMENT ON TABLE market_data_ohlcv IS 'OHLCV candlestick data for various timeframes';

-- ============================================================================
-- Market Data Quotes Table (Real-time quotes)
-- ============================================================================
CREATE TABLE market_data_quotes (
    time TIMESTAMP WITH TIME ZONE NOT NULL,
    instrument_id BIGINT NOT NULL REFERENCES instruments(instrument_id),
    bid_price DECIMAL(20, 8),
    bid_size DECIMAL(20, 8),
    ask_price DECIMAL(20, 8),
    ask_size DECIMAL(20, 8),
    spread DECIMAL(20, 8) GENERATED ALWAYS AS (ask_price - bid_price) STORED,
    mid_price DECIMAL(20, 8) GENERATED ALWAYS AS ((bid_price + ask_price) / 2) STORED,
    PRIMARY KEY (time, instrument_id)
);

-- Convert to hypertable
SELECT create_hypertable('market_data_quotes', 'time');

-- Create indexes
CREATE INDEX idx_quotes_instrument_time ON market_data_quotes (instrument_id, time DESC);

-- Add compression policy
ALTER TABLE market_data_quotes SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'instrument_id'
);

SELECT add_compression_policy('market_data_quotes', INTERVAL '1 day');

-- Add retention policy (keep quotes for 30 days)
SELECT add_retention_policy('market_data_quotes', INTERVAL '30 days');

COMMENT ON TABLE market_data_quotes IS 'Real-time bid/ask quotes';

-- ============================================================================
-- Market Data Tickers Table (Latest prices)
-- ============================================================================
CREATE TABLE market_data_tickers (
    instrument_id BIGINT PRIMARY KEY REFERENCES instruments(instrument_id),
    last_price DECIMAL(20, 8) NOT NULL,
    bid_price DECIMAL(20, 8),
    ask_price DECIMAL(20, 8),
    volume_24h DECIMAL(20, 8),
    high_24h DECIMAL(20, 8),
    low_24h DECIMAL(20, 8),
    open_24h DECIMAL(20, 8),
    price_change_24h DECIMAL(20, 8),
    price_change_pct_24h DECIMAL(10, 4),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_tickers_updated_at ON market_data_tickers(updated_at DESC);

COMMENT ON TABLE market_data_tickers IS 'Latest ticker data for instruments';

-- ============================================================================
-- Market Data Trades Table (Tick data)
-- ============================================================================
CREATE TABLE market_data_trades (
    time TIMESTAMP WITH TIME ZONE NOT NULL,
    instrument_id BIGINT NOT NULL REFERENCES instruments(instrument_id),
    trade_id VARCHAR(50),
    price DECIMAL(20, 8) NOT NULL,
    quantity DECIMAL(20, 8) NOT NULL,
    side VARCHAR(10) CHECK (side IN ('buy', 'sell')),
    PRIMARY KEY (time, instrument_id, trade_id)
);

-- Convert to hypertable
SELECT create_hypertable('market_data_trades', 'time');

-- Create indexes
CREATE INDEX idx_market_trades_instrument_time ON market_data_trades (instrument_id, time DESC);

-- Add compression policy
ALTER TABLE market_data_trades SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'instrument_id'
);

SELECT add_compression_policy('market_data_trades', INTERVAL '3 days');

-- Add retention policy (keep tick data for 90 days)
SELECT add_retention_policy('market_data_trades', INTERVAL '90 days');

COMMENT ON TABLE market_data_trades IS 'Tick-by-tick trade data';

-- ============================================================================
-- Continuous Aggregates for Performance
-- ============================================================================

-- 1-hour OHLCV from 1-minute data
CREATE MATERIALIZED VIEW market_data_ohlcv_1h
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS time,
    instrument_id,
    first(open, time) AS open,
    max(high) AS high,
    min(low) AS low,
    last(close, time) AS close,
    sum(volume) AS volume,
    sum(quote_volume) AS quote_volume,
    sum(trades_count) AS trades_count
FROM market_data_ohlcv
WHERE timeframe = '1m'
GROUP BY time_bucket('1 hour', time), instrument_id;

-- Add refresh policy
SELECT add_continuous_aggregate_policy('market_data_ohlcv_1h',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

-- Daily OHLCV from 1-hour data
CREATE MATERIALIZED VIEW market_data_ohlcv_1d
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', time) AS time,
    instrument_id,
    first(open, time) AS open,
    max(high) AS high,
    min(low) AS low,
    last(close, time) AS close,
    sum(volume) AS volume,
    sum(quote_volume) AS quote_volume,
    sum(trades_count) AS trades_count
FROM market_data_ohlcv_1h
GROUP BY time_bucket('1 day', time), instrument_id;

-- Add refresh policy
SELECT add_continuous_aggregate_policy('market_data_ohlcv_1d',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day');
