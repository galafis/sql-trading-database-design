-- ============================================================================
-- Unit Tests for Core Database Functions
-- Author: Gabriel Demetrios Lafis
-- Description: pgTAP unit tests for trading system functions
-- ============================================================================

-- Start transaction
BEGIN;

-- Load pgTAP extension
SELECT plan(20);

-- ============================================================================
-- Test: Database Schema Exists
-- ============================================================================

SELECT has_table('users', 'Users table should exist');
SELECT has_table('accounts', 'Accounts table should exist');
SELECT has_table('instruments', 'Instruments table should exist');
SELECT has_table('orders', 'Orders table should exist');
SELECT has_table('trades', 'Trades table should exist');
SELECT has_table('positions', 'Positions table should exist');
SELECT has_table('transactions', 'Transactions table should exist');
SELECT has_table('audit_log', 'Audit log table should exist');

-- ============================================================================
-- Test: Functions Exist
-- ============================================================================

SELECT has_function('place_order', 'place_order function should exist');
SELECT has_function('update_position', 'update_position function should exist');
SELECT has_function('calculate_realized_pnl', 'calculate_realized_pnl function should exist');
SELECT has_function('calculate_unrealized_pnl', 'calculate_unrealized_pnl function should exist');

-- ============================================================================
-- Test: Views Exist
-- ============================================================================

SELECT has_view('v_portfolio_summary', 'Portfolio summary view should exist');
SELECT has_view('v_position_details', 'Position details view should exist');
SELECT has_view('v_risk_metrics', 'Risk metrics view should exist');
SELECT has_view('v_daily_pnl_summary', 'Daily P&L summary view should exist');

-- ============================================================================
-- Test: Triggers Exist
-- ============================================================================

SELECT has_trigger('users', 'audit_users', 'Users table should have audit trigger');
SELECT has_trigger('orders', 'validate_order_trigger', 'Orders table should have validation trigger');

-- ============================================================================
-- Test: Indexes Exist
-- ============================================================================

SELECT has_index('users', 'idx_users_email', 'Users email index should exist');
SELECT has_index('orders', 'idx_orders_account_id', 'Orders account_id index should exist');

-- Finish the tests and clean up
SELECT * FROM finish();
ROLLBACK;
