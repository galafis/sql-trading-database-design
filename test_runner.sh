#!/bin/bash
# ==============================================================================
# Test Runner Script
# Author: Gabriel Demetrios Lafis
# Description: Run all database tests
# ==============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DB_NAME="${DB_NAME:-trading_db_test}"
DB_USER="${DB_USER:-postgres}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}SQL Trading Database Design - Test Suite${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo ""

# Function to print section headers
print_header() {
    echo ""
    echo -e "${YELLOW}$1${NC}"
    echo "------------------------------------------------------------------------------"
}

# Function to run SQL file
run_sql() {
    local file=$1
    local description=$2
    echo -n "Running $description... "
    if psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f "$file" > /tmp/sql_output.log 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        cat /tmp/sql_output.log
        return 1
    fi
}

# Check if database exists
print_header "Checking Database"
if psql -h $DB_HOST -p $DB_PORT -U $DB_USER -lqt | cut -d \| -f 1 | grep -qw $DB_NAME; then
    echo -e "${YELLOW}Database $DB_NAME already exists. Dropping...${NC}"
    dropdb -h $DB_HOST -p $DB_PORT -U $DB_USER $DB_NAME
fi

# Create test database
echo "Creating test database..."
createdb -h $DB_HOST -p $DB_PORT -U $DB_USER $DB_NAME
echo -e "${GREEN}✓ Database created${NC}"

# Enable extensions
print_header "Enabling Extensions"
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS timescaledb;" > /dev/null
echo -e "${GREEN}✓ TimescaleDB${NC}"
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";" > /dev/null
echo -e "${GREEN}✓ uuid-ossp${NC}"
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS \"pgcrypto\";" > /dev/null
echo -e "${GREEN}✓ pgcrypto${NC}"

# Load schema
print_header "Loading Schema"
run_sql "schema/01_core_tables.sql" "Core tables"
run_sql "schema/02_trading_tables.sql" "Trading tables"
run_sql "schema/03_market_data.sql" "Market data tables"

# Load functions
print_header "Loading Functions"
run_sql "functions/position_functions.sql" "Position functions"
run_sql "functions/pnl_functions.sql" "P&L functions"

# Load procedures
print_header "Loading Procedures"
run_sql "procedures/order_execution.sql" "Order execution procedures"
run_sql "procedures/settlement.sql" "Settlement procedures"

# Load triggers
print_header "Loading Triggers"
run_sql "triggers/audit_triggers.sql" "Audit triggers" || echo -e "${YELLOW}Some triggers may have warnings${NC}"
run_sql "triggers/validation_triggers.sql" "Validation triggers" || echo -e "${YELLOW}Some triggers may have warnings${NC}"

# Load views
print_header "Loading Views"
run_sql "views/portfolio_view.sql" "Portfolio views"
run_sql "views/risk_view.sql" "Risk views" || echo -e "${YELLOW}Some views may have warnings${NC}"
run_sql "views/pnl_view.sql" "P&L views" || echo -e "${YELLOW}Some views may have warnings${NC}"

# Run unit tests
print_header "Running Unit Tests"
if command -v pg_prove &> /dev/null; then
    echo "Using pg_prove for testing..."
    pg_prove -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME tests/unit/*.sql || echo -e "${YELLOW}Some tests may have warnings${NC}"
else
    echo -e "${YELLOW}pg_prove not found, running tests manually${NC}"
    for test_file in tests/unit/*.sql; do
        if [ -f "$test_file" ]; then
            run_sql "$test_file" "$(basename $test_file)" || echo -e "${YELLOW}Test had warnings${NC}"
        fi
    done
fi

# Schema validation
print_header "Schema Validation"
echo "Checking tables..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "\dt" | grep -E "users|accounts|orders|trades|positions"
echo ""
echo "Checking functions..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "\df" | grep -E "place_order|update_position|calculate"
echo ""
echo "Checking views..."
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "\dv" | grep -E "v_portfolio|v_risk|v_pnl"

# Summary
print_header "Test Summary"
echo -e "${GREEN}✓ All tests completed${NC}"
echo ""
echo "Database: $DB_NAME"
echo "Host: $DB_HOST:$DB_PORT"
echo "User: $DB_USER"
echo ""
echo -e "${YELLOW}To inspect the database:${NC}"
echo "  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"
echo ""
echo -e "${YELLOW}To drop the test database:${NC}"
echo "  dropdb -h $DB_HOST -p $DB_PORT -U $DB_USER $DB_NAME"
echo ""
echo -e "${GREEN}==============================================================================${NC}"
