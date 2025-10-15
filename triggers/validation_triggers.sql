-- ============================================================================
-- Validation Triggers
-- Author: Gabriel Demetrios Lafis
-- Description: Triggers for data validation and business rules enforcement
-- ============================================================================

-- ============================================================================
-- Function: Validate Order
-- ============================================================================
CREATE OR REPLACE FUNCTION validate_order()
RETURNS TRIGGER AS $$
DECLARE
    v_account RECORD;
    v_instrument RECORD;
    v_required_margin DECIMAL;
BEGIN
    -- Get account details
    SELECT * INTO v_account
    FROM accounts
    WHERE account_id = NEW.account_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account % not found', NEW.account_id;
    END IF;
    
    IF NOT v_account.is_active THEN
        RAISE EXCEPTION 'Account % is not active', NEW.account_id;
    END IF;
    
    -- Get instrument details
    SELECT * INTO v_instrument
    FROM instruments
    WHERE instrument_id = NEW.instrument_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Instrument % not found', NEW.instrument_id;
    END IF;
    
    IF NOT v_instrument.is_tradeable THEN
        RAISE EXCEPTION 'Instrument % is not tradeable', NEW.instrument_id;
    END IF;
    
    -- Validate quantity
    IF NEW.quantity <= 0 THEN
        RAISE EXCEPTION 'Order quantity must be positive';
    END IF;
    
    IF NEW.quantity < v_instrument.min_trade_size THEN
        RAISE EXCEPTION 'Order quantity % is below minimum trade size %', 
            NEW.quantity, v_instrument.min_trade_size;
    END IF;
    
    IF v_instrument.max_trade_size IS NOT NULL AND NEW.quantity > v_instrument.max_trade_size THEN
        RAISE EXCEPTION 'Order quantity % exceeds maximum trade size %', 
            NEW.quantity, v_instrument.max_trade_size;
    END IF;
    
    -- Validate price for limit orders
    IF NEW.order_type = 'limit' THEN
        IF NEW.price IS NULL THEN
            RAISE EXCEPTION 'Limit orders must have a price';
        END IF;
        
        IF NEW.price <= 0 THEN
            RAISE EXCEPTION 'Order price must be positive';
        END IF;
        
        IF v_instrument.min_price IS NOT NULL AND NEW.price < v_instrument.min_price THEN
            RAISE EXCEPTION 'Order price % is below minimum price %', 
                NEW.price, v_instrument.min_price;
        END IF;
    END IF;
    
    -- Validate stop price for stop orders
    IF NEW.order_type IN ('stop', 'stop_limit') THEN
        IF NEW.stop_price IS NULL THEN
            RAISE EXCEPTION 'Stop orders must have a stop price';
        END IF;
        
        IF NEW.stop_price <= 0 THEN
            RAISE EXCEPTION 'Stop price must be positive';
        END IF;
    END IF;
    
    -- Check available balance for buy orders
    IF NEW.side = 'buy' THEN
        v_required_margin := NEW.quantity * COALESCE(NEW.price, NEW.stop_price, 0);
        
        IF v_account.available_balance < v_required_margin THEN
            RAISE EXCEPTION 'Insufficient balance. Required: %, Available: %',
                v_required_margin, v_account.available_balance;
        END IF;
    END IF;
    
    -- Set default time in force
    IF NEW.time_in_force IS NULL THEN
        NEW.time_in_force := 'GTC';
    END IF;
    
    -- Set initial status
    IF NEW.status IS NULL THEN
        NEW.status := 'pending';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_order IS 'Validate order before insertion';

DROP TRIGGER IF EXISTS validate_order_trigger ON orders;
CREATE TRIGGER validate_order_trigger
    BEFORE INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION validate_order();

-- ============================================================================
-- Function: Validate Trade
-- ============================================================================
CREATE OR REPLACE FUNCTION validate_trade()
RETURNS TRIGGER AS $$
DECLARE
    v_order RECORD;
BEGIN
    -- Get order details
    SELECT * INTO v_order
    FROM orders
    WHERE order_id = NEW.order_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % not found', NEW.order_id;
    END IF;
    
    -- Validate trade matches order
    IF NEW.account_id != v_order.account_id THEN
        RAISE EXCEPTION 'Trade account does not match order account';
    END IF;
    
    IF NEW.instrument_id != v_order.instrument_id THEN
        RAISE EXCEPTION 'Trade instrument does not match order instrument';
    END IF;
    
    IF NEW.side != v_order.side THEN
        RAISE EXCEPTION 'Trade side does not match order side';
    END IF;
    
    -- Validate quantity
    IF NEW.quantity <= 0 THEN
        RAISE EXCEPTION 'Trade quantity must be positive';
    END IF;
    
    IF NEW.quantity > (v_order.quantity - v_order.filled_quantity) THEN
        RAISE EXCEPTION 'Trade quantity exceeds remaining order quantity';
    END IF;
    
    -- Validate price
    IF NEW.price <= 0 THEN
        RAISE EXCEPTION 'Trade price must be positive';
    END IF;
    
    -- Calculate value if not set
    IF NEW.value IS NULL THEN
        NEW.value := NEW.quantity * NEW.price;
    END IF;
    
    -- Set default commission if not set
    IF NEW.commission IS NULL THEN
        NEW.commission := 0;
    END IF;
    
    -- Set execution time if not set
    IF NEW.executed_at IS NULL THEN
        NEW.executed_at := CURRENT_TIMESTAMP;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_trade IS 'Validate trade before insertion';

DROP TRIGGER IF EXISTS validate_trade_trigger ON trades;
CREATE TRIGGER validate_trade_trigger
    BEFORE INSERT ON trades
    FOR EACH ROW
    EXECUTE FUNCTION validate_trade();

-- ============================================================================
-- Function: Validate Account Balance
-- ============================================================================
CREATE OR REPLACE FUNCTION validate_account_balance()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        -- Ensure balance doesn't go negative for cash accounts
        IF NEW.account_type = 'cash' AND NEW.balance < 0 THEN
            RAISE EXCEPTION 'Cash account balance cannot be negative';
        END IF;
        
        -- Ensure available balance is not greater than balance
        IF NEW.available_balance > NEW.balance THEN
            RAISE EXCEPTION 'Available balance cannot exceed total balance';
        END IF;
        
        -- Check margin requirements for margin accounts
        IF NEW.account_type = 'margin' AND NEW.margin_used > NEW.balance * NEW.leverage THEN
            RAISE EXCEPTION 'Margin used exceeds maximum allowed by leverage';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_account_balance IS 'Validate account balance constraints';

DROP TRIGGER IF EXISTS validate_account_balance_trigger ON accounts;
CREATE TRIGGER validate_account_balance_trigger
    BEFORE UPDATE ON accounts
    FOR EACH ROW
    EXECUTE FUNCTION validate_account_balance();

-- ============================================================================
-- Function: Validate Position
-- ============================================================================
CREATE OR REPLACE FUNCTION validate_position()
RETURNS TRIGGER AS $$
BEGIN
    -- Validate quantity
    IF NEW.quantity <= 0 THEN
        RAISE EXCEPTION 'Position quantity must be positive';
    END IF;
    
    -- Validate average entry price
    IF NEW.average_entry_price <= 0 THEN
        RAISE EXCEPTION 'Average entry price must be positive';
    END IF;
    
    -- Validate side
    IF NEW.side NOT IN ('long', 'short') THEN
        RAISE EXCEPTION 'Position side must be long or short';
    END IF;
    
    -- Set default values
    IF NEW.opened_at IS NULL THEN
        NEW.opened_at := CURRENT_TIMESTAMP;
    END IF;
    
    IF NEW.current_price IS NULL THEN
        NEW.current_price := NEW.average_entry_price;
    END IF;
    
    IF NEW.unrealized_pnl IS NULL THEN
        NEW.unrealized_pnl := 0;
    END IF;
    
    IF NEW.realized_pnl IS NULL THEN
        NEW.realized_pnl := 0;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_position IS 'Validate position before insertion or update';

DROP TRIGGER IF EXISTS validate_position_trigger ON positions;
CREATE TRIGGER validate_position_trigger
    BEFORE INSERT OR UPDATE ON positions
    FOR EACH ROW
    EXECUTE FUNCTION validate_position();

-- ============================================================================
-- Function: Validate Transaction
-- ============================================================================
CREATE OR REPLACE FUNCTION validate_transaction()
RETURNS TRIGGER AS $$
DECLARE
    v_account RECORD;
BEGIN
    -- Get account details
    SELECT * INTO v_account
    FROM accounts
    WHERE account_id = NEW.account_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account % not found', NEW.account_id;
    END IF;
    
    -- Validate amount
    IF NEW.amount <= 0 THEN
        RAISE EXCEPTION 'Transaction amount must be positive';
    END IF;
    
    -- Validate withdrawal doesn't exceed balance
    IF NEW.transaction_type = 'withdrawal' THEN
        IF NEW.amount > v_account.available_balance THEN
            RAISE EXCEPTION 'Withdrawal amount % exceeds available balance %',
                NEW.amount, v_account.available_balance;
        END IF;
    END IF;
    
    -- Set default status
    IF NEW.status IS NULL THEN
        NEW.status := 'pending';
    END IF;
    
    -- Set execution time if not set
    IF NEW.executed_at IS NULL THEN
        NEW.executed_at := CURRENT_TIMESTAMP;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_transaction IS 'Validate transaction before insertion';

DROP TRIGGER IF EXISTS validate_transaction_trigger ON transactions;
CREATE TRIGGER validate_transaction_trigger
    BEFORE INSERT ON transactions
    FOR EACH ROW
    EXECUTE FUNCTION validate_transaction();

-- ============================================================================
-- Function: Prevent Duplicate Active Orders
-- ============================================================================
CREATE OR REPLACE FUNCTION prevent_duplicate_orders()
RETURNS TRIGGER AS $$
DECLARE
    v_duplicate_count INTEGER;
BEGIN
    IF NEW.client_order_id IS NOT NULL THEN
        SELECT COUNT(*) INTO v_duplicate_count
        FROM orders
        WHERE client_order_id = NEW.client_order_id
            AND account_id = NEW.account_id
            AND status IN ('pending', 'partial');
        
        IF v_duplicate_count > 0 THEN
            RAISE EXCEPTION 'Duplicate order with client_order_id % already exists', 
                NEW.client_order_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION prevent_duplicate_orders IS 'Prevent duplicate orders with same client_order_id';

DROP TRIGGER IF EXISTS prevent_duplicate_orders_trigger ON orders;
CREATE TRIGGER prevent_duplicate_orders_trigger
    BEFORE INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION prevent_duplicate_orders();

-- ============================================================================
-- Function: Validate User KYC
-- ============================================================================
CREATE OR REPLACE FUNCTION validate_user_kyc()
RETURNS TRIGGER AS $$
BEGIN
    -- Ensure KYC status is valid
    IF NEW.kyc_status NOT IN ('pending', 'approved', 'rejected') THEN
        RAISE EXCEPTION 'Invalid KYC status: %', NEW.kyc_status;
    END IF;
    
    -- Update last_login_at on login
    IF TG_OP = 'UPDATE' AND OLD.last_login_at IS DISTINCT FROM NEW.last_login_at THEN
        NEW.updated_at := CURRENT_TIMESTAMP;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_user_kyc IS 'Validate user KYC status';

DROP TRIGGER IF EXISTS validate_user_kyc_trigger ON users;
CREATE TRIGGER validate_user_kyc_trigger
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION validate_user_kyc();

-- ============================================================================
-- Function: Enforce Trading Hours
-- ============================================================================
CREATE OR REPLACE FUNCTION enforce_trading_hours()
RETURNS TRIGGER AS $$
DECLARE
    v_instrument RECORD;
    v_current_time TIME;
    v_current_day INTEGER;
BEGIN
    -- Get instrument trading hours
    SELECT * INTO v_instrument
    FROM instruments
    WHERE instrument_id = NEW.instrument_id;
    
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;
    
    v_current_time := CURRENT_TIME;
    v_current_day := EXTRACT(DOW FROM CURRENT_DATE);
    
    -- Check if trading is allowed (simplified - can be extended with exchange hours)
    IF NOT v_instrument.is_tradeable THEN
        RAISE EXCEPTION 'Trading is not allowed for instrument %', NEW.instrument_id;
    END IF;
    
    -- Weekend check (0 = Sunday, 6 = Saturday)
    IF v_current_day IN (0, 6) AND v_instrument.instrument_type != 'crypto' THEN
        RAISE EXCEPTION 'Trading is not allowed on weekends for this instrument';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION enforce_trading_hours IS 'Enforce trading hours restrictions';

DROP TRIGGER IF EXISTS enforce_trading_hours_trigger ON orders;
CREATE TRIGGER enforce_trading_hours_trigger
    BEFORE INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION enforce_trading_hours();
