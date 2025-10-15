-- ============================================================================
-- Settlement Procedures
-- Author: Gabriel Demetrios Lafis
-- Description: Procedures for trade settlement and reconciliation
-- ============================================================================

-- ============================================================================
-- Procedure: Settle Trade
-- ============================================================================
CREATE OR REPLACE FUNCTION settle_trade(
    p_trade_id BIGINT
)
RETURNS BOOLEAN AS $$
DECLARE
    v_trade RECORD;
    v_settlement_amount DECIMAL;
BEGIN
    -- Get trade details
    SELECT * INTO v_trade
    FROM trades
    WHERE trade_id = p_trade_id
    FOR UPDATE;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Trade not found';
    END IF;
    
    IF v_trade.settlement_status = 'settled' THEN
        RAISE EXCEPTION 'Trade already settled';
    END IF;
    
    -- Calculate settlement amount (value + commission)
    v_settlement_amount := v_trade.value + v_trade.commission;
    
    -- Update account balance based on trade side
    IF v_trade.side = 'buy' THEN
        -- Deduct for buy trades
        UPDATE accounts
        SET 
            balance = balance - v_settlement_amount,
            available_balance = available_balance - v_settlement_amount
        WHERE account_id = v_trade.account_id;
    ELSE
        -- Add for sell trades
        UPDATE accounts
        SET 
            balance = balance + v_settlement_amount - v_trade.commission,
            available_balance = available_balance + v_settlement_amount - v_trade.commission
        WHERE account_id = v_trade.account_id;
    END IF;
    
    -- Mark trade as settled
    UPDATE trades
    SET 
        settlement_status = 'settled',
        settlement_date = CURRENT_TIMESTAMP
    WHERE trade_id = p_trade_id;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION settle_trade IS 'Settle a trade and update account balance';

-- ============================================================================
-- Procedure: Batch Settlement
-- ============================================================================
CREATE OR REPLACE FUNCTION batch_settle_trades(
    p_settlement_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    settled_count INTEGER,
    failed_count INTEGER,
    total_settled_value DECIMAL
) AS $$
DECLARE
    v_trade RECORD;
    v_settled_count INTEGER := 0;
    v_failed_count INTEGER := 0;
    v_total_value DECIMAL := 0;
BEGIN
    FOR v_trade IN
        SELECT trade_id, value
        FROM trades
        WHERE DATE_TRUNC('day', executed_at) = p_settlement_date
            AND (settlement_status IS NULL OR settlement_status = 'pending')
    LOOP
        BEGIN
            PERFORM settle_trade(v_trade.trade_id);
            v_settled_count := v_settled_count + 1;
            v_total_value := v_total_value + v_trade.value;
        EXCEPTION
            WHEN OTHERS THEN
                v_failed_count := v_failed_count + 1;
                RAISE NOTICE 'Failed to settle trade %: %', v_trade.trade_id, SQLERRM;
        END;
    END LOOP;
    
    RETURN QUERY
    SELECT v_settled_count, v_failed_count, v_total_value;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION batch_settle_trades IS 'Batch settle all pending trades for a date';

-- ============================================================================
-- Procedure: Reconcile Account
-- ============================================================================
CREATE OR REPLACE FUNCTION reconcile_account(
    p_account_id BIGINT
)
RETURNS TABLE (
    expected_balance DECIMAL,
    actual_balance DECIMAL,
    difference DECIMAL,
    is_balanced BOOLEAN
) AS $$
DECLARE
    v_initial_balance DECIMAL;
    v_total_deposits DECIMAL;
    v_total_withdrawals DECIMAL;
    v_total_pnl DECIMAL;
    v_expected_balance DECIMAL;
    v_actual_balance DECIMAL;
BEGIN
    -- Get current balance
    SELECT balance INTO v_actual_balance
    FROM accounts
    WHERE account_id = p_account_id;
    
    -- Calculate expected balance from transactions
    SELECT 
        COALESCE(SUM(CASE WHEN transaction_type = 'deposit' THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN transaction_type = 'withdrawal' THEN amount ELSE 0 END), 0)
    INTO v_total_deposits, v_total_withdrawals
    FROM transactions
    WHERE account_id = p_account_id;
    
    -- Get total P&L from closed positions
    SELECT COALESCE(SUM(realized_pnl), 0)
    INTO v_total_pnl
    FROM position_history
    WHERE account_id = p_account_id;
    
    -- Calculate expected balance
    v_expected_balance := v_total_deposits - v_total_withdrawals + v_total_pnl;
    
    RETURN QUERY
    SELECT 
        v_expected_balance,
        v_actual_balance,
        v_actual_balance - v_expected_balance AS difference,
        ABS(v_actual_balance - v_expected_balance) < 0.01 AS is_balanced;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION reconcile_account IS 'Reconcile account balance with transactions and P&L';

-- ============================================================================
-- Procedure: Process End of Day Settlement
-- ============================================================================
CREATE OR REPLACE FUNCTION process_eod_settlement(
    p_settlement_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    total_trades INTEGER,
    settled_trades INTEGER,
    failed_trades INTEGER,
    total_volume DECIMAL,
    total_commission DECIMAL
) AS $$
DECLARE
    v_batch_result RECORD;
BEGIN
    -- Settle all pending trades
    SELECT * INTO v_batch_result
    FROM batch_settle_trades(p_settlement_date);
    
    -- Update positions with latest market prices
    PERFORM update_all_positions_pnl();
    
    -- Return settlement summary
    RETURN QUERY
    SELECT 
        COUNT(*)::INTEGER AS total_trades,
        v_batch_result.settled_count,
        v_batch_result.failed_count,
        v_batch_result.total_settled_value,
        COALESCE(SUM(commission), 0) AS total_commission
    FROM trades
    WHERE DATE_TRUNC('day', executed_at) = p_settlement_date;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION process_eod_settlement IS 'Process end-of-day settlement for all trades';

-- ============================================================================
-- Procedure: Calculate Margin Requirements
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_margin_requirements(
    p_account_id BIGINT
)
RETURNS TABLE (
    total_margin_required DECIMAL,
    margin_used DECIMAL,
    available_margin DECIMAL,
    margin_level DECIMAL,
    is_margin_call BOOLEAN
) AS $$
DECLARE
    v_account RECORD;
    v_total_margin_required DECIMAL := 0;
    v_position RECORD;
BEGIN
    -- Get account details
    SELECT * INTO v_account
    FROM accounts
    WHERE account_id = p_account_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account not found';
    END IF;
    
    -- Calculate total margin required for all positions
    FOR v_position IN
        SELECT 
            p.*,
            i.margin_requirement
        FROM positions p
        JOIN instruments i ON p.instrument_id = i.instrument_id
        WHERE p.account_id = p_account_id
    LOOP
        v_total_margin_required := v_total_margin_required + 
            (v_position.quantity * v_position.current_price * v_position.margin_requirement);
    END LOOP;
    
    RETURN QUERY
    SELECT 
        v_total_margin_required,
        v_account.margin_used,
        v_account.balance - v_total_margin_required AS available_margin,
        CASE 
            WHEN v_total_margin_required > 0 THEN
                (v_account.balance / v_total_margin_required) * 100
            ELSE NULL
        END AS margin_level,
        v_account.balance < v_total_margin_required AS is_margin_call;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_margin_requirements IS 'Calculate margin requirements and check for margin calls';

-- ============================================================================
-- Procedure: Process Corporate Action
-- ============================================================================
CREATE OR REPLACE FUNCTION process_corporate_action(
    p_instrument_id BIGINT,
    p_action_type VARCHAR,
    p_ratio DECIMAL,
    p_effective_date DATE
)
RETURNS INTEGER AS $$
DECLARE
    v_position RECORD;
    v_affected_count INTEGER := 0;
BEGIN
    -- Process stock split or reverse split
    IF p_action_type IN ('split', 'reverse_split') THEN
        FOR v_position IN
            SELECT position_id, quantity, average_entry_price
            FROM positions
            WHERE instrument_id = p_instrument_id
            FOR UPDATE
        LOOP
            UPDATE positions
            SET 
                quantity = quantity * p_ratio,
                average_entry_price = average_entry_price / p_ratio,
                updated_at = CURRENT_TIMESTAMP
            WHERE position_id = v_position.position_id;
            
            v_affected_count := v_affected_count + 1;
        END LOOP;
    
    -- Process dividend
    ELSIF p_action_type = 'dividend' THEN
        FOR v_position IN
            SELECT p.position_id, p.quantity, p.account_id
            FROM positions p
            WHERE p.instrument_id = p_instrument_id
                AND p.side = 'long'
        LOOP
            -- Credit dividend to account
            UPDATE accounts
            SET balance = balance + (v_position.quantity * p_ratio)
            WHERE account_id = v_position.account_id;
            
            -- Get updated balance
            DECLARE v_new_balance DECIMAL;
            SELECT balance INTO v_new_balance 
            FROM accounts 
            WHERE account_id = v_position.account_id;
            
            -- Record dividend transaction
            INSERT INTO transactions (
                account_id,
                transaction_type,
                amount,
                balance_after,
                currency,
                reference_id,
                reference_type,
                description,
                created_at
            ) VALUES (
                v_position.account_id,
                'dividend',
                v_position.quantity * p_ratio,
                v_new_balance,
                'USD',
                v_position.position_id,
                'position',
                'Dividend payment for instrument ' || p_instrument_id,
                p_effective_date
            );
            
            v_affected_count := v_affected_count + 1;
        END LOOP;
    END IF;
    
    RETURN v_affected_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION process_corporate_action IS 'Process corporate actions (splits, dividends)';

-- ============================================================================
-- Procedure: Mark to Market
-- ============================================================================
CREATE OR REPLACE FUNCTION mark_to_market(
    p_account_id BIGINT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_updated_count INTEGER := 0;
    v_position RECORD;
BEGIN
    FOR v_position IN
        SELECT 
            p.position_id,
            p.account_id,
            p.instrument_id,
            p.side,
            p.quantity,
            p.average_entry_price,
            t.last_price
        FROM positions p
        JOIN market_data_tickers t ON p.instrument_id = t.instrument_id
        WHERE p_account_id IS NULL OR p.account_id = p_account_id
    LOOP
        UPDATE positions
        SET 
            current_price = v_position.last_price,
            unrealized_pnl = calculate_unrealized_pnl(
                v_position.average_entry_price,
                v_position.last_price,
                v_position.quantity,
                v_position.side
            ),
            updated_at = CURRENT_TIMESTAMP
        WHERE position_id = v_position.position_id;
        
        v_updated_count := v_updated_count + 1;
    END LOOP;
    
    RETURN v_updated_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION mark_to_market IS 'Update all positions with current market prices';
