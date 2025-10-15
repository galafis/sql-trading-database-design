-- ============================================================================
-- Audit Triggers
-- Author: Gabriel Demetrios Lafis
-- Description: Triggers for comprehensive audit logging
-- ============================================================================

-- ============================================================================
-- Function: Audit Trigger Function
-- ============================================================================
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    v_old_data JSON;
    v_new_data JSON;
    v_operation_type VARCHAR(10);
BEGIN
    -- Determine operation type
    IF TG_OP = 'INSERT' THEN
        v_operation_type := 'INSERT';
        v_new_data := row_to_json(NEW);
        v_old_data := NULL;
    ELSIF TG_OP = 'UPDATE' THEN
        v_operation_type := 'UPDATE';
        v_old_data := row_to_json(OLD);
        v_new_data := row_to_json(NEW);
    ELSIF TG_OP = 'DELETE' THEN
        v_operation_type := 'DELETE';
        v_old_data := row_to_json(OLD);
        v_new_data := NULL;
    END IF;
    
    -- Insert audit record
    INSERT INTO audit_log (
        table_name,
        record_id,
        operation_type,
        old_data,
        new_data,
        changed_by,
        changed_at
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        v_operation_type,
        v_old_data,
        v_new_data,
        current_user,
        CURRENT_TIMESTAMP
    );
    
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION audit_trigger_function IS 'Generic audit logging function for all tables';

-- ============================================================================
-- Apply Audit Triggers to Critical Tables
-- ============================================================================

-- Audit users table
DROP TRIGGER IF EXISTS audit_users ON users;
CREATE TRIGGER audit_users
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger_function();

-- Audit accounts table
DROP TRIGGER IF EXISTS audit_accounts ON accounts;
CREATE TRIGGER audit_accounts
    AFTER INSERT OR UPDATE OR DELETE ON accounts
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger_function();

-- Audit orders table
DROP TRIGGER IF EXISTS audit_orders ON orders;
CREATE TRIGGER audit_orders
    AFTER INSERT OR UPDATE OR DELETE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger_function();

-- Audit trades table
DROP TRIGGER IF EXISTS audit_trades ON trades;
CREATE TRIGGER audit_trades
    AFTER INSERT OR UPDATE OR DELETE ON trades
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger_function();

-- Audit positions table
DROP TRIGGER IF EXISTS audit_positions ON positions;
CREATE TRIGGER audit_positions
    AFTER INSERT OR UPDATE OR DELETE ON positions
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger_function();

-- Audit transactions table
DROP TRIGGER IF EXISTS audit_transactions ON transactions;
CREATE TRIGGER audit_transactions
    AFTER INSERT OR UPDATE OR DELETE ON transactions
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger_function();

-- ============================================================================
-- Function: Security Audit for Sensitive Operations
-- ============================================================================
CREATE OR REPLACE FUNCTION security_audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
    -- Log security-sensitive operations
    IF TG_OP = 'UPDATE' THEN
        -- Log password changes
        IF TG_TABLE_NAME = 'users' AND OLD.password_hash != NEW.password_hash THEN
            INSERT INTO audit_log (
                table_name,
                record_id,
                operation_type,
                description,
                changed_by,
                changed_at
            ) VALUES (
                'users',
                NEW.user_id,
                'PASSWORD_CHANGE',
                'Password changed for user: ' || NEW.username,
                current_user,
                CURRENT_TIMESTAMP
            );
        END IF;
        
        -- Log KYC status changes
        IF TG_TABLE_NAME = 'users' AND OLD.kyc_status != NEW.kyc_status THEN
            INSERT INTO audit_log (
                table_name,
                record_id,
                operation_type,
                description,
                changed_by,
                changed_at
            ) VALUES (
                'users',
                NEW.user_id,
                'KYC_STATUS_CHANGE',
                'KYC status changed from ' || OLD.kyc_status || ' to ' || NEW.kyc_status,
                current_user,
                CURRENT_TIMESTAMP
            );
        END IF;
        
        -- Log account balance changes
        IF TG_TABLE_NAME = 'accounts' AND OLD.balance != NEW.balance THEN
            INSERT INTO audit_log (
                table_name,
                record_id,
                operation_type,
                description,
                changed_by,
                changed_at
            ) VALUES (
                'accounts',
                NEW.account_id,
                'BALANCE_CHANGE',
                'Balance changed from ' || OLD.balance || ' to ' || NEW.balance,
                current_user,
                CURRENT_TIMESTAMP
            );
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION security_audit_trigger IS 'Audit security-sensitive operations';

-- Apply security audit triggers
DROP TRIGGER IF EXISTS security_audit_users ON users;
CREATE TRIGGER security_audit_users
    AFTER UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION security_audit_trigger();

DROP TRIGGER IF EXISTS security_audit_accounts ON accounts;
CREATE TRIGGER security_audit_accounts
    AFTER UPDATE ON accounts
    FOR EACH ROW
    EXECUTE FUNCTION security_audit_trigger();

-- ============================================================================
-- Function: Order Status Change Audit
-- ============================================================================
CREATE OR REPLACE FUNCTION audit_order_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.status != NEW.status THEN
        INSERT INTO audit_log (
            table_name,
            record_id,
            operation_type,
            description,
            old_data,
            new_data,
            changed_by,
            changed_at
        ) VALUES (
            'orders',
            NEW.order_id,
            'STATUS_CHANGE',
            'Order status changed from ' || OLD.status || ' to ' || NEW.status,
            json_build_object('status', OLD.status, 'filled_quantity', OLD.filled_quantity),
            json_build_object('status', NEW.status, 'filled_quantity', NEW.filled_quantity),
            current_user,
            CURRENT_TIMESTAMP
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION audit_order_status_change IS 'Audit order status changes';

DROP TRIGGER IF EXISTS audit_order_status ON orders;
CREATE TRIGGER audit_order_status
    AFTER UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION audit_order_status_change();

-- ============================================================================
-- Function: Trade Execution Audit
-- ============================================================================
CREATE OR REPLACE FUNCTION audit_trade_execution()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (
            table_name,
            record_id,
            operation_type,
            description,
            new_data,
            changed_by,
            changed_at
        ) VALUES (
            'trades',
            NEW.trade_id,
            'TRADE_EXECUTED',
            'Trade executed: ' || NEW.side || ' ' || NEW.quantity || ' @ ' || NEW.price,
            row_to_json(NEW),
            current_user,
            CURRENT_TIMESTAMP
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION audit_trade_execution IS 'Audit trade executions';

DROP TRIGGER IF EXISTS audit_trade_exec ON trades;
CREATE TRIGGER audit_trade_exec
    AFTER INSERT ON trades
    FOR EACH ROW
    EXECUTE FUNCTION audit_trade_execution();

-- ============================================================================
-- Function: Large Transaction Alert
-- ============================================================================
CREATE OR REPLACE FUNCTION audit_large_transactions()
RETURNS TRIGGER AS $$
DECLARE
    v_threshold DECIMAL := 100000;
BEGIN
    IF TG_OP = 'INSERT' AND NEW.amount > v_threshold THEN
        INSERT INTO audit_log (
            table_name,
            record_id,
            operation_type,
            description,
            new_data,
            changed_by,
            changed_at,
            severity
        ) VALUES (
            'transactions',
            NEW.transaction_id,
            'LARGE_TRANSACTION',
            'Large transaction detected: ' || NEW.transaction_type || ' ' || NEW.amount,
            row_to_json(NEW),
            current_user,
            CURRENT_TIMESTAMP,
            'HIGH'
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION audit_large_transactions IS 'Audit large transactions';

DROP TRIGGER IF EXISTS audit_large_trans ON transactions;
CREATE TRIGGER audit_large_trans
    AFTER INSERT ON transactions
    FOR EACH ROW
    EXECUTE FUNCTION audit_large_transactions();
