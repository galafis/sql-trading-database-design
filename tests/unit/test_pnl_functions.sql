-- ============================================================================
-- Unit Tests for P&L Functions
-- Author: Gabriel Demetrios Lafis
-- Description: Tests for P&L calculation functions
-- ============================================================================

BEGIN;
SELECT plan(10);

-- ============================================================================
-- Test: Calculate Realized P&L for Long Position
-- ============================================================================

SELECT is(
    calculate_realized_pnl(100.00, 110.00, 10.00, 'long', 5.00),
    95.00,
    'Long position with profit should calculate correctly'
);

SELECT is(
    calculate_realized_pnl(100.00, 90.00, 10.00, 'long', 5.00),
    -105.00,
    'Long position with loss should calculate correctly'
);

-- ============================================================================
-- Test: Calculate Realized P&L for Short Position
-- ============================================================================

SELECT is(
    calculate_realized_pnl(100.00, 90.00, 10.00, 'short', 5.00),
    95.00,
    'Short position with profit should calculate correctly'
);

SELECT is(
    calculate_realized_pnl(100.00, 110.00, 10.00, 'short', 5.00),
    -105.00,
    'Short position with loss should calculate correctly'
);

-- ============================================================================
-- Test: Calculate Unrealized P&L for Long Position
-- ============================================================================

SELECT is(
    calculate_unrealized_pnl(100.00, 110.00, 10.00, 'long'),
    100.00,
    'Unrealized P&L for long position should calculate correctly'
);

SELECT is(
    calculate_unrealized_pnl(100.00, 90.00, 10.00, 'long'),
    -100.00,
    'Unrealized P&L for long position with loss should calculate correctly'
);

-- ============================================================================
-- Test: Calculate Unrealized P&L for Short Position
-- ============================================================================

SELECT is(
    calculate_unrealized_pnl(100.00, 90.00, 10.00, 'short'),
    100.00,
    'Unrealized P&L for short position should calculate correctly'
);

SELECT is(
    calculate_unrealized_pnl(100.00, 110.00, 10.00, 'short'),
    -100.00,
    'Unrealized P&L for short position with loss should calculate correctly'
);

-- ============================================================================
-- Test: Calculate P&L Percentage
-- ============================================================================

SELECT is(
    calculate_pnl_percentage(100.00, 100.00, 10.00),
    10.00,
    'P&L percentage should calculate correctly'
);

SELECT is(
    calculate_pnl_percentage(-100.00, 100.00, 10.00),
    -10.00,
    'Negative P&L percentage should calculate correctly'
);

SELECT * FROM finish();
ROLLBACK;
