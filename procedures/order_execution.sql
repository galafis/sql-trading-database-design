-- ============================================================================
-- Order Execution Procedures
-- Author: Gabriel Demetrios Lafis
-- Description: Stored procedures for order placement and execution
-- ============================================================================

-- ============================================================================
-- Procedure: Place Order
-- ============================================================================
CREATE OR REPLACE FUNCTION place_order(
    p_account_id BIGINT,
    p_instrument_id BIGINT,
    p_order_type VARCHAR,
    p_side VARCHAR,
    p_quantity DECIMAL,
    p_price DECIMAL DEFAULT NULL,
    p_stop_price DECIMAL DEFAULT NULL,
    p_time_in_force VARCHAR DEFAULT 'GTC',
    p_client_order_id VARCHAR DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_order_id BIGINT;
    v_account_balance DECIMAL;
    v_required_margin DECIMAL;
    v_instrument_price DECIMAL;
BEGIN
    -- Validate account
    SELECT balance INTO v_account_balance
    FROM accounts
    WHERE account_id = p_account_id AND is_active = true;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account not found or inactive';
    END IF;
    
    -- Validate instrument
    IF NOT EXISTS (SELECT 1 FROM instruments WHERE instrument_id = p_instrument_id AND is_tradeable = true) THEN
        RAISE EXCEPTION 'Instrument not found or not tradeable';
    END IF;
    
    -- Get current price for margin calculation
    SELECT last_price INTO v_instrument_price
    FROM market_data_tickers
    WHERE instrument_id = p_instrument_id;
    
    IF v_instrument_price IS NULL THEN
        v_instrument_price := COALESCE(p_price, p_stop_price, 0);
    END IF;
    
    -- Calculate required margin
    v_required_margin := v_instrument_price * p_quantity;
    
    -- Check available balance
    IF v_account_balance < v_required_margin THEN
        RAISE EXCEPTION 'Insufficient balance. Required: %, Available: %', v_required_margin, v_account_balance;
    END IF;
    
    -- Insert order
    INSERT INTO orders (
        account_id,
        instrument_id,
        order_type,
        side,
        quantity,
        price,
        stop_price,
        time_in_force,
        client_order_id,
        status
    ) VALUES (
        p_account_id,
        p_instrument_id,
        p_order_type,
        p_side,
        p_quantity,
        p_price,
        p_stop_price,
        p_time_in_force,
        p_client_order_id,
        'open'
    ) RETURNING order_id INTO v_order_id;
    
    -- Update account available balance
    UPDATE accounts
    SET available_balance = available_balance - v_required_margin
    WHERE account_id = p_account_id;
    
    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION place_order IS 'Place a new trading order with validation';

-- ============================================================================
-- Procedure: Execute Trade
-- ============================================================================
CREATE OR REPLACE FUNCTION execute_trade(
    p_order_id BIGINT,
    p_quantity DECIMAL,
    p_price DECIMAL
)
RETURNS BIGINT AS $$
DECLARE
    v_trade_id BIGINT;
    v_order RECORD;
    v_trade_value DECIMAL;
    v_commission DECIMAL;
    v_new_filled_quantity DECIMAL;
BEGIN
    -- Get order details
    SELECT * INTO v_order
    FROM orders
    WHERE order_id = p_order_id
    FOR UPDATE;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found';
    END IF;
    
    IF v_order.status NOT IN ('open', 'partially_filled') THEN
        RAISE EXCEPTION 'Order is not open for execution';
    END IF;
    
    -- Validate quantity
    IF p_quantity > (v_order.quantity - v_order.filled_quantity) THEN
        RAISE EXCEPTION 'Execution quantity exceeds remaining order quantity';
    END IF;
    
    -- Calculate trade value and commission (0.1%)
    v_trade_value := p_quantity * p_price;
    v_commission := v_trade_value * 0.001;
    
    -- Insert trade
    INSERT INTO trades (
        order_id,
        account_id,
        instrument_id,
        side,
        quantity,
        price,
        value,
        commission
    ) VALUES (
        p_order_id,
        v_order.account_id,
        v_order.instrument_id,
        v_order.side,
        p_quantity,
        p_price,
        v_trade_value,
        v_commission
    ) RETURNING trade_id INTO v_trade_id;
    
    -- Update order
    v_new_filled_quantity := v_order.filled_quantity + p_quantity;
    
    UPDATE orders
    SET 
        filled_quantity = v_new_filled_quantity,
        average_fill_price = ((COALESCE(average_fill_price, 0) * filled_quantity) + (p_price * p_quantity)) / v_new_filled_quantity,
        commission = COALESCE(commission, 0) + v_commission,
        status = CASE 
            WHEN v_new_filled_quantity >= quantity THEN 'filled'
            ELSE 'partially_filled'
        END,
        filled_at = CASE 
            WHEN v_new_filled_quantity >= quantity THEN CURRENT_TIMESTAMP
            ELSE filled_at
        END
    WHERE order_id = p_order_id;
    
    -- Update or create position
    PERFORM update_position(
        v_order.account_id,
        v_order.instrument_id,
        v_order.side,
        p_quantity,
        p_price
    );
    
    -- Record transaction
    INSERT INTO transactions (
        account_id,
        transaction_type,
        amount,
        balance_after,
        reference_id,
        reference_type,
        description
    )
    SELECT 
        v_order.account_id,
        'trade',
        CASE 
            WHEN v_order.side = 'buy' THEN -(v_trade_value + v_commission)
            ELSE v_trade_value - v_commission
        END,
        (SELECT balance FROM accounts WHERE account_id = v_order.account_id),
        v_trade_id,
        'trade',
        format('Trade execution for order %s', p_order_id);
    
    RETURN v_trade_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION execute_trade IS 'Execute a trade for an order';

-- ============================================================================
-- Procedure: Cancel Order
-- ============================================================================
CREATE OR REPLACE FUNCTION cancel_order(
    p_order_id BIGINT,
    p_reason TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_order RECORD;
    v_refund_amount DECIMAL;
BEGIN
    -- Get order details
    SELECT * INTO v_order
    FROM orders
    WHERE order_id = p_order_id
    FOR UPDATE;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found';
    END IF;
    
    IF v_order.status NOT IN ('open', 'partially_filled') THEN
        RAISE EXCEPTION 'Order cannot be cancelled (status: %)', v_order.status;
    END IF;
    
    -- Calculate refund amount for unfilled quantity
    SELECT last_price * (v_order.quantity - v_order.filled_quantity) INTO v_refund_amount
    FROM market_data_tickers
    WHERE instrument_id = v_order.instrument_id;
    
    -- Update order status
    UPDATE orders
    SET 
        status = 'cancelled',
        reject_reason = p_reason,
        cancelled_at = CURRENT_TIMESTAMP
    WHERE order_id = p_order_id;
    
    -- Refund margin for unfilled quantity
    UPDATE accounts
    SET available_balance = available_balance + COALESCE(v_refund_amount, 0)
    WHERE account_id = v_order.account_id;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cancel_order IS 'Cancel an open order';
