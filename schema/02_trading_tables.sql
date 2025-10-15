-- ============================================================================
-- Trading Tables for Trading System
-- Author: Gabriel Demetrios Lafis
-- Description: Orders, trades, positions, and transactions
-- ============================================================================

-- ============================================================================
-- Orders Table
-- ============================================================================
CREATE TABLE orders (
    order_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id),
    instrument_id BIGINT NOT NULL REFERENCES instruments(instrument_id),
    order_type VARCHAR(20) NOT NULL CHECK (order_type IN ('market', 'limit', 'stop', 'stop_limit')),
    side VARCHAR(10) NOT NULL CHECK (side IN ('buy', 'sell')),
    quantity DECIMAL(20, 8) NOT NULL CHECK (quantity > 0),
    filled_quantity DECIMAL(20, 8) DEFAULT 0.00 CHECK (filled_quantity >= 0),
    price DECIMAL(20, 8),
    stop_price DECIMAL(20, 8),
    time_in_force VARCHAR(10) DEFAULT 'GTC' CHECK (time_in_force IN ('GTC', 'IOC', 'FOK', 'DAY')),
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'open', 'partially_filled', 'filled', 'cancelled', 'rejected')),
    reject_reason TEXT,
    client_order_id VARCHAR(50),
    average_fill_price DECIMAL(20, 8),
    commission DECIMAL(20, 8) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    filled_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_orders_account_id ON orders(account_id);
CREATE INDEX idx_orders_instrument_id ON orders(instrument_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);
CREATE INDEX idx_orders_client_order_id ON orders(client_order_id);

COMMENT ON TABLE orders IS 'Trading orders placed by users';

-- ============================================================================
-- Trades Table
-- ============================================================================
CREATE TABLE trades (
    trade_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES orders(order_id),
    account_id BIGINT NOT NULL REFERENCES accounts(account_id),
    instrument_id BIGINT NOT NULL REFERENCES instruments(instrument_id),
    side VARCHAR(10) NOT NULL CHECK (side IN ('buy', 'sell')),
    quantity DECIMAL(20, 8) NOT NULL CHECK (quantity > 0),
    price DECIMAL(20, 8) NOT NULL CHECK (price > 0),
    value DECIMAL(20, 8) NOT NULL,
    commission DECIMAL(20, 8) DEFAULT 0.00,
    trade_type VARCHAR(20) DEFAULT 'regular' CHECK (trade_type IN ('regular', 'liquidation', 'settlement')),
    settlement_status VARCHAR(20) DEFAULT 'pending' CHECK (settlement_status IN ('pending', 'settled', 'failed')),
    settlement_date TIMESTAMP WITH TIME ZONE,
    executed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_trades_order_id ON trades(order_id);
CREATE INDEX idx_trades_account_id ON trades(account_id);
CREATE INDEX idx_trades_instrument_id ON trades(instrument_id);
CREATE INDEX idx_trades_executed_at ON trades(executed_at DESC);

COMMENT ON TABLE trades IS 'Executed trades (order fills)';

-- ============================================================================
-- Positions Table
-- ============================================================================
CREATE TABLE positions (
    position_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id),
    instrument_id BIGINT NOT NULL REFERENCES instruments(instrument_id),
    side VARCHAR(10) NOT NULL CHECK (side IN ('long', 'short')),
    quantity DECIMAL(20, 8) NOT NULL CHECK (quantity >= 0),
    average_entry_price DECIMAL(20, 8) NOT NULL CHECK (average_entry_price > 0),
    current_price DECIMAL(20, 8),
    unrealized_pnl DECIMAL(20, 8) DEFAULT 0.00,
    realized_pnl DECIMAL(20, 8) DEFAULT 0.00,
    total_pnl DECIMAL(20, 8) GENERATED ALWAYS AS (unrealized_pnl + realized_pnl) STORED,
    margin_used DECIMAL(20, 8) DEFAULT 0.00,
    opened_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(account_id, instrument_id, side)
);

CREATE INDEX idx_positions_account_id ON positions(account_id);
CREATE INDEX idx_positions_instrument_id ON positions(instrument_id);
CREATE INDEX idx_positions_opened_at ON positions(opened_at DESC);

COMMENT ON TABLE positions IS 'Current open positions';

-- ============================================================================
-- Position History Table
-- ============================================================================
CREATE TABLE position_history (
    history_id BIGSERIAL PRIMARY KEY,
    position_id BIGINT NOT NULL,
    account_id BIGINT NOT NULL,
    instrument_id BIGINT NOT NULL,
    side VARCHAR(10) NOT NULL,
    quantity DECIMAL(20, 8) NOT NULL,
    entry_price DECIMAL(20, 8) NOT NULL,
    exit_price DECIMAL(20, 8),
    realized_pnl DECIMAL(20, 8),
    holding_period INTERVAL,
    opened_at TIMESTAMP WITH TIME ZONE,
    closed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_position_history_account_id ON position_history(account_id);
CREATE INDEX idx_position_history_instrument_id ON position_history(instrument_id);
CREATE INDEX idx_position_history_closed_at ON position_history(closed_at DESC);

COMMENT ON TABLE position_history IS 'Historical record of closed positions';

-- ============================================================================
-- Transactions Table
-- ============================================================================
CREATE TABLE transactions (
    transaction_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id),
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('deposit', 'withdrawal', 'trade', 'commission', 'interest', 'dividend', 'adjustment')),
    amount DECIMAL(20, 8) NOT NULL,
    balance_after DECIMAL(20, 8) NOT NULL,
    currency CHAR(3) DEFAULT 'USD',
    reference_id BIGINT,
    reference_type VARCHAR(50),
    description TEXT,
    status VARCHAR(20) DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed', 'reversed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_transactions_account_id ON transactions(account_id);
CREATE INDEX idx_transactions_type ON transactions(transaction_type);
CREATE INDEX idx_transactions_created_at ON transactions(created_at DESC);
CREATE INDEX idx_transactions_reference ON transactions(reference_type, reference_id);

COMMENT ON TABLE transactions IS 'Financial transactions for accounts';

-- ============================================================================
-- Update Triggers
-- ============================================================================
CREATE TRIGGER update_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_positions_updated_at
    BEFORE UPDATE ON positions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();


-- ============================================================================
-- Audit Trigger Function for Orders
-- ============================================================================
CREATE OR REPLACE FUNCTION audit_orders_changes_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, new_data, changed_by)
        VALUES (TG_TABLE_NAME, NEW.order_id, TG_OP, to_jsonb(NEW), NEW.account_id); -- Assuming account_id is the user context
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, old_data, new_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.order_id, TG_OP, to_jsonb(OLD), to_jsonb(NEW), NEW.account_id);
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, old_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.order_id, TG_OP, to_jsonb(OLD), OLD.account_id);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_orders_changes
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION audit_orders_changes_trigger();

-- ============================================================================
-- Audit Trigger Function for Trades
-- ============================================================================
CREATE OR REPLACE FUNCTION audit_trades_changes_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, new_data, changed_by)
        VALUES (TG_TABLE_NAME, NEW.trade_id, TG_OP, to_jsonb(NEW), NEW.account_id);
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, old_data, new_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.trade_id, TG_OP, to_jsonb(OLD), to_jsonb(NEW), NEW.account_id);
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, old_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.trade_id, TG_OP, to_jsonb(OLD), OLD.account_id);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_trades_changes
AFTER INSERT OR UPDATE OR DELETE ON trades
FOR EACH ROW EXECUTE FUNCTION audit_trades_changes_trigger();

-- ============================================================================
-- Audit Trigger Function for Positions
-- ============================================================================
CREATE OR REPLACE FUNCTION audit_positions_changes_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, new_data, changed_by)
        VALUES (TG_TABLE_NAME, NEW.position_id, TG_OP, to_jsonb(NEW), NEW.account_id);
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, old_data, new_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.position_id, TG_OP, to_jsonb(OLD), to_jsonb(NEW), NEW.account_id);
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, old_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.position_id, TG_OP, to_jsonb(OLD), OLD.account_id);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_positions_changes
AFTER INSERT OR UPDATE OR DELETE ON positions
FOR EACH ROW EXECUTE FUNCTION audit_positions_changes_trigger();

-- ============================================================================
-- Audit Trigger Function for Position History
-- ============================================================================
CREATE OR REPLACE FUNCTION audit_position_history_changes_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, new_data, changed_by)
        VALUES (TG_TABLE_NAME, NEW.history_id, TG_OP, to_jsonb(NEW), NEW.account_id);
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, old_data, new_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.history_id, TG_OP, to_jsonb(OLD), to_jsonb(NEW), NEW.account_id);
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, old_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.history_id, TG_OP, to_jsonb(OLD), OLD.account_id);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_position_history_changes
AFTER INSERT OR UPDATE OR DELETE ON position_history
FOR EACH ROW EXECUTE FUNCTION audit_position_history_changes_trigger();

-- ============================================================================
-- Audit Trigger Function for Transactions
-- ============================================================================
CREATE OR REPLACE FUNCTION audit_transactions_changes_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, new_data, changed_by)
        VALUES (TG_TABLE_NAME, NEW.transaction_id, TG_OP, to_jsonb(NEW), NEW.account_id);
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, old_data, new_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.transaction_id, TG_OP, to_jsonb(OLD), to_jsonb(NEW), NEW.account_id);
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_log (table_name, record_id, operation_type, old_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.transaction_id, TG_OP, to_jsonb(OLD), OLD.account_id);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_transactions_changes
AFTER INSERT OR UPDATE OR DELETE ON transactions
FOR EACH ROW EXECUTE FUNCTION audit_transactions_changes_trigger();

