-- ============================================================================
-- Position Management Functions
-- Author: Gabriel Demetrios Lafis
-- Description: Functions for managing trading positions
-- ============================================================================

-- ============================================================================
-- Function: Update Position
-- ============================================================================
CREATE OR REPLACE FUNCTION update_position(
    p_account_id BIGINT,
    p_instrument_id BIGINT,
    p_side VARCHAR,
    p_quantity DECIMAL,
    p_price DECIMAL
)
RETURNS VOID AS $$
DECLARE
    v_position RECORD;
    v_position_side VARCHAR;
    v_new_quantity DECIMAL;
    v_new_avg_price DECIMAL;
BEGIN
    -- Determine position side based on order side
    v_position_side := CASE WHEN p_side = 'buy' THEN 'long' ELSE 'short' END;
    
    -- Try to get existing position
    SELECT * INTO v_position
    FROM positions
    WHERE account_id = p_account_id 
        AND instrument_id = p_instrument_id 
        AND side = v_position_side
    FOR UPDATE;
    
    IF FOUND THEN
        -- Update existing position
        v_new_quantity := v_position.quantity + p_quantity;
        v_new_avg_price := ((v_position.average_entry_price * v_position.quantity) + (p_price * p_quantity)) / v_new_quantity;
        
        UPDATE positions
        SET 
            quantity = v_new_quantity,
            average_entry_price = v_new_avg_price,
            updated_at = CURRENT_TIMESTAMP
        WHERE position_id = v_position.position_id;
    ELSE
        -- Create new position
        INSERT INTO positions (
            account_id,
            instrument_id,
            side,
            quantity,
            average_entry_price
        ) VALUES (
            p_account_id,
            p_instrument_id,
            v_position_side,
            p_quantity,
            p_price
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_position IS 'Update or create a position after trade execution';

-- ============================================================================
-- Function: Close Position
-- ============================================================================
CREATE OR REPLACE FUNCTION close_position(
    p_position_id BIGINT,
    p_exit_price DECIMAL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_position RECORD;
    v_realized_pnl DECIMAL;
BEGIN
    -- Get position details
    SELECT * INTO v_position
    FROM positions
    WHERE position_id = p_position_id
    FOR UPDATE;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Position not found';
    END IF;
    
    -- Calculate realized P&L
    IF v_position.side = 'long' THEN
        v_realized_pnl := (p_exit_price - v_position.average_entry_price) * v_position.quantity;
    ELSE
        v_realized_pnl := (v_position.average_entry_price - p_exit_price) * v_position.quantity;
    END IF;
    
    -- Archive position to history
    INSERT INTO position_history (
        position_id,
        account_id,
        instrument_id,
        side,
        quantity,
        entry_price,
        exit_price,
        realized_pnl,
        holding_period,
        opened_at
    ) VALUES (
        v_position.position_id,
        v_position.account_id,
        v_position.instrument_id,
        v_position.side,
        v_position.quantity,
        v_position.average_entry_price,
        p_exit_price,
        v_realized_pnl,
        CURRENT_TIMESTAMP - v_position.opened_at,
        v_position.opened_at
    );
    
    -- Delete position
    DELETE FROM positions WHERE position_id = p_position_id;
    
    -- Update account balance
    UPDATE accounts
    SET balance = balance + v_realized_pnl
    WHERE account_id = v_position.account_id;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION close_position IS 'Close a position and record P&L';

-- ============================================================================
-- Function: Calculate Position P&L
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_position_pnl(
    p_position_id BIGINT
)
RETURNS TABLE (
    unrealized_pnl DECIMAL,
    realized_pnl DECIMAL,
    total_pnl DECIMAL,
    pnl_percentage DECIMAL
) AS $$
DECLARE
    v_position RECORD;
    v_current_price DECIMAL;
    v_unrealized_pnl DECIMAL;
BEGIN
    -- Get position details
    SELECT * INTO v_position
    FROM positions
    WHERE position_id = p_position_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Position not found';
    END IF;
    
    -- Get current market price
    SELECT last_price INTO v_current_price
    FROM market_data_tickers
    WHERE instrument_id = v_position.instrument_id;
    
    IF v_current_price IS NULL THEN
        RAISE EXCEPTION 'Current price not available for instrument';
    END IF;
    
    -- Calculate unrealized P&L
    IF v_position.side = 'long' THEN
        v_unrealized_pnl := (v_current_price - v_position.average_entry_price) * v_position.quantity;
    ELSE
        v_unrealized_pnl := (v_position.average_entry_price - v_current_price) * v_position.quantity;
    END IF;
    
    -- Return results
    RETURN QUERY
    SELECT 
        v_unrealized_pnl AS unrealized_pnl,
        v_position.realized_pnl,
        v_unrealized_pnl + v_position.realized_pnl AS total_pnl,
        (v_unrealized_pnl / (v_position.average_entry_price * v_position.quantity)) * 100 AS pnl_percentage;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_position_pnl IS 'Calculate P&L for a position';

-- ============================================================================
-- Function: Update All Positions P&L
-- ============================================================================
CREATE OR REPLACE FUNCTION update_all_positions_pnl()
RETURNS INTEGER AS $$
DECLARE
    v_position RECORD;
    v_current_price DECIMAL;
    v_unrealized_pnl DECIMAL;
    v_updated_count INTEGER := 0;
BEGIN
    FOR v_position IN 
        SELECT p.*, t.last_price
        FROM positions p
        JOIN market_data_tickers t ON p.instrument_id = t.instrument_id
    LOOP
        -- Calculate unrealized P&L
        IF v_position.side = 'long' THEN
            v_unrealized_pnl := (v_position.last_price - v_position.average_entry_price) * v_position.quantity;
        ELSE
            v_unrealized_pnl := (v_position.average_entry_price - v_position.last_price) * v_position.quantity;
        END IF;
        
        -- Update position
        UPDATE positions
        SET 
            current_price = v_position.last_price,
            unrealized_pnl = v_unrealized_pnl,
            updated_at = CURRENT_TIMESTAMP
        WHERE position_id = v_position.position_id;
        
        v_updated_count := v_updated_count + 1;
    END LOOP;
    
    RETURN v_updated_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_all_positions_pnl IS 'Update unrealized P&L for all open positions';

-- ============================================================================
-- Function: Get Account Positions Summary
-- ============================================================================
CREATE OR REPLACE FUNCTION get_account_positions_summary(
    p_account_id BIGINT
)
RETURNS TABLE (
    total_positions INTEGER,
    total_unrealized_pnl DECIMAL,
    total_realized_pnl DECIMAL,
    total_pnl DECIMAL,
    winning_positions INTEGER,
    losing_positions INTEGER,
    win_rate DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*)::INTEGER AS total_positions,
        SUM(unrealized_pnl) AS total_unrealized_pnl,
        SUM(realized_pnl) AS total_realized_pnl,
        SUM(unrealized_pnl + realized_pnl) AS total_pnl,
        COUNT(*) FILTER (WHERE unrealized_pnl > 0)::INTEGER AS winning_positions,
        COUNT(*) FILTER (WHERE unrealized_pnl < 0)::INTEGER AS losing_positions,
        CASE 
            WHEN COUNT(*) > 0 THEN 
                (COUNT(*) FILTER (WHERE unrealized_pnl > 0)::DECIMAL / COUNT(*)) * 100
            ELSE 0
        END AS win_rate
    FROM positions
    WHERE account_id = p_account_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_account_positions_summary IS 'Get summary of positions for an account';
