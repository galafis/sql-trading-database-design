# CI/CD Database Test Fix Summary

## Problem
The CI/CD Pipeline "Run Database Tests" job was failing after 59 seconds with SQL syntax errors preventing the database schema from loading correctly.

## Root Cause Analysis

### Issue 1: Settlement Procedure Syntax Error
**File**: `procedures/settlement.sql` (line 299)  
**Error**: Invalid DECLARE statement inside FOR loop

```sql
-- INCORRECT CODE:
ELSIF p_action_type = 'dividend' THEN
    FOR v_position IN ... LOOP
        UPDATE accounts ...
        
        -- This is invalid PL/pgSQL syntax
        DECLARE v_new_balance DECIMAL;
        SELECT balance INTO v_new_balance ...
    END LOOP;
```

**Issue**: PL/pgSQL does not allow DECLARE statements inside loops. All variable declarations must be in the DECLARE block at the beginning of the function.

### Issue 2: P&L View Nested Window Functions
**File**: `views/pnl_view.sql` (lines 223-241)  
**Error**: Nested window functions are not allowed in PostgreSQL

```sql
-- INCORRECT CODE:
MAX(SUM(d.daily_pnl) OVER (
    PARTITION BY a.account_id 
    ORDER BY d.trade_date
)) OVER (
    PARTITION BY a.account_id 
    ORDER BY d.trade_date
) AS running_max_pnl
```

**Issue**: PostgreSQL does not support nesting window functions like `MAX(SUM(...) OVER (...)) OVER (...)`.

## Solutions Implemented

### Fix 1: Settlement Procedure
Moved the variable declaration from inside the loop to the DECLARE section:

```sql
-- CORRECTED CODE:
CREATE OR REPLACE FUNCTION process_corporate_action(...)
RETURNS INTEGER AS $$
DECLARE
    v_position RECORD;
    v_affected_count INTEGER := 0;
    v_new_balance DECIMAL;  -- Moved here
BEGIN
    ELSIF p_action_type = 'dividend' THEN
        FOR v_position IN ... LOOP
            UPDATE accounts ...
            
            -- No DECLARE needed here anymore
            SELECT balance INTO v_new_balance ...
        END LOOP;
END;
```

### Fix 2: P&L View
Refactored the view to use an intermediate CTE that calculates cumulative P&L first, then applies window functions:

```sql
-- CORRECTED CODE:
WITH daily_pnl AS (...),
pnl_with_cumulative AS (
    SELECT 
        ...,
        SUM(d.daily_pnl) OVER (...) AS cumulative_pnl,
        ...
    FROM accounts a
    JOIN daily_pnl d ON a.account_id = d.account_id
)
SELECT 
    ...,
    cumulative_pnl,
    
    -- Now we can apply window functions without nesting
    MAX(cumulative_pnl) OVER (
        PARTITION BY account_id 
        ORDER BY trade_date
    ) AS running_max_pnl,
    
    cumulative_pnl - MAX(cumulative_pnl) OVER (
        PARTITION BY account_id 
        ORDER BY trade_date
    ) AS drawdown
FROM pnl_with_cumulative
```

## Testing Results

### Local Testing
All unit tests pass successfully:
- ✅ 20 tests in `test_schema.sql` - all passed
- ✅ 10 tests in `test_pnl_functions.sql` - all passed
- ✅ All schema files load without errors
- ✅ All functions load without errors
- ✅ All procedures load without errors
- ✅ All triggers load without errors
- ✅ All views load without errors

### What Was Tested
1. Schema validation (tables, functions, views, triggers, indexes exist)
2. P&L calculation functions (realized/unrealized P&L for long/short positions)
3. P&L percentage calculations
4. Complete database setup from scratch

## Files Modified
1. `procedures/settlement.sql` - 2 lines changed (1 added, 1 removed)
2. `views/pnl_view.sql` - 78 lines changed (40 insertions, 38 deletions)

## Impact
- ✅ CI/CD pipeline should now pass all database tests
- ✅ Database schema loads completely without errors
- ✅ All pgTAP unit tests execute successfully
- ✅ No functional changes - only syntax fixes

## Verification Steps for CI/CD
The GitHub Actions workflow should now:
1. ✅ Install PostgreSQL with TimescaleDB
2. ✅ Enable required extensions
3. ✅ Load all schema files successfully
4. ✅ Load all functions, procedures, triggers, and views successfully
5. ✅ Install pgTAP and pg_prove
6. ✅ Run all unit tests successfully
7. ✅ Validate schema structure

## Conclusion
The two SQL syntax errors have been fixed with minimal, surgical changes. All tests now pass locally, and the CI/CD pipeline should execute successfully.
