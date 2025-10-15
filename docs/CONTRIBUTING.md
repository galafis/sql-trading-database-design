# Contributing to SQL Trading Database Design

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing to this project.

---

## Code of Conduct

### Our Pledge

We pledge to make participation in our project a harassment-free experience for everyone, regardless of age, body size, disability, ethnicity, gender identity and expression, level of experience, education, socio-economic status, nationality, personal appearance, race, religion, or sexual identity and orientation.

### Our Standards

**Positive behavior includes:**
- Using welcoming and inclusive language
- Being respectful of differing viewpoints
- Gracefully accepting constructive criticism
- Focusing on what is best for the community
- Showing empathy towards other community members

**Unacceptable behavior includes:**
- Trolling, insulting/derogatory comments, and personal attacks
- Public or private harassment
- Publishing others' private information without permission
- Other conduct which could reasonably be considered inappropriate

---

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the issue list as you might find that you don't need to create one. When creating a bug report, include as many details as possible:

**Bug Report Template:**
```markdown
**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Run query '...'
2. Execute function '...'
3. See error

**Expected behavior**
What you expected to happen.

**Actual behavior**
What actually happened.

**Environment:**
- PostgreSQL version:
- TimescaleDB version:
- OS:
- Additional context:

**SQL or Error Messages**
```sql
-- Include relevant SQL code or error messages
```
```

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

- **Clear title** and description of the enhancement
- **Use case**: Why is this enhancement useful?
- **Examples**: Provide code examples if applicable
- **Alternatives**: Have you considered alternatives?

### Pull Requests

1. **Fork the repository** and create your branch from `master`
2. **Make your changes** following our coding standards
3. **Test your changes** thoroughly
4. **Update documentation** if needed
5. **Submit a pull request** with a clear description

---

## Development Setup

### Prerequisites

```bash
# Install PostgreSQL 15+
sudo apt-get install postgresql-15

# Install TimescaleDB
sudo add-apt-repository ppa:timescale/timescaledb-ppa
sudo apt-get update
sudo apt-get install timescaledb-2-postgresql-15

# Install pgTAP for testing
sudo apt-get install pgtap
```

### Setting Up Development Environment

```bash
# Clone the repository
git clone https://github.com/galafis/sql-trading-database-design.git
cd sql-trading-database-design

# Create development database
createdb trading_db_dev

# Enable extensions
psql -d trading_db_dev -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
psql -d trading_db_dev -c "CREATE EXTENSION IF NOT EXISTS pgtap;"

# Run schema creation
psql -d trading_db_dev -f schema/01_core_tables.sql
psql -d trading_db_dev -f schema/02_trading_tables.sql
psql -d trading_db_dev -f schema/03_market_data.sql

# Load functions and procedures
psql -d trading_db_dev -f functions/position_functions.sql
psql -d trading_db_dev -f functions/pnl_functions.sql
psql -d trading_db_dev -f procedures/order_execution.sql
psql -d trading_db_dev -f procedures/settlement.sql

# Load triggers
psql -d trading_db_dev -f triggers/audit_triggers.sql
psql -d trading_db_dev -f triggers/validation_triggers.sql

# Load views
psql -d trading_db_dev -f views/portfolio_view.sql
psql -d trading_db_dev -f views/risk_view.sql
psql -d trading_db_dev -f views/pnl_view.sql
```

---

## Coding Standards

### SQL Style Guide

**General Principles:**
- Use uppercase for SQL keywords: `SELECT`, `FROM`, `WHERE`, `JOIN`
- Use lowercase for table and column names
- Use snake_case for identifiers
- Indent for readability
- Add comments for complex logic

**Good Example:**
```sql
-- Calculate daily P&L for an account
SELECT 
    account_id,
    DATE_TRUNC('day', executed_at) AS trade_date,
    COUNT(*) AS total_trades,
    SUM(value) AS total_volume,
    SUM(CASE 
        WHEN side = 'sell' THEN value - commission
        ELSE -(value + commission)
    END) AS daily_pnl
FROM trades
WHERE account_id = 123
    AND executed_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY account_id, DATE_TRUNC('day', executed_at)
ORDER BY trade_date DESC;
```

**Bad Example:**
```sql
-- Avoid this style
select account_id,sum(value) from trades where account_id=123 group by account_id;
```

### Function and Procedure Standards

```sql
-- ============================================================================
-- Function: [Function Name]
-- Description: [Brief description]
-- Parameters:
--   p_param1: [Description]
--   p_param2: [Description]
-- Returns: [Return type and description]
-- ============================================================================
CREATE OR REPLACE FUNCTION function_name(
    p_param1 DATATYPE,
    p_param2 DATATYPE
)
RETURNS RETURN_TYPE AS $$
DECLARE
    v_variable DATATYPE;
BEGIN
    -- Implementation
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION function_name IS 'Detailed description';
```

### Table and Column Naming

- Tables: Plural nouns (`users`, `orders`, `trades`)
- Columns: Descriptive, snake_case (`user_id`, `created_at`, `average_price`)
- Foreign keys: `{parent_table}_id` (`user_id`, `account_id`)
- Timestamps: `created_at`, `updated_at`, `executed_at`
- Booleans: `is_active`, `is_tradeable`

---

## Testing Guidelines

### Writing Unit Tests

All new functions should include unit tests using pgTAP:

```sql
-- tests/unit/test_my_function.sql
BEGIN;
SELECT plan(5);

-- Test 1: Basic functionality
SELECT is(
    my_function(100, 200),
    300,
    'Function should return sum of inputs'
);

-- Test 2: Edge case
SELECT is(
    my_function(0, 0),
    0,
    'Function should handle zero inputs'
);

-- Test 3: Null handling
SELECT is(
    my_function(NULL, 100),
    NULL,
    'Function should return NULL for NULL input'
);

-- Test 4: Type checking
SELECT has_function('my_function');

-- Test 5: Performance
SELECT ok(
    (SELECT my_function(1000000, 2000000)) IS NOT NULL,
    'Function should handle large numbers'
);

SELECT * FROM finish();
ROLLBACK;
```

### Running Tests

```bash
# Run all unit tests
pg_prove tests/unit/*.sql

# Run specific test
pg_prove tests/unit/test_pnl_functions.sql

# Run with verbose output
pg_prove -v tests/unit/*.sql
```

---

## Documentation Standards

### Code Documentation

- **Functions/Procedures**: Include header comments with description, parameters, and return values
- **Complex queries**: Add inline comments explaining logic
- **Views**: Document purpose and key columns
- **Indexes**: Comment on why index was created

### Markdown Documentation

- Use clear, concise language
- Include code examples
- Provide context and use cases
- Keep examples up to date
- Use proper formatting and structure

---

## Pull Request Process

### Before Submitting

1. **Update tests**: Add or update tests for your changes
2. **Run tests**: Ensure all tests pass
3. **Update documentation**: Update relevant docs
4. **Check style**: Follow coding standards
5. **Test manually**: Verify changes work as expected

### PR Template

```markdown
## Description
[Describe what this PR does]

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] All tests pass
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex code
- [ ] Documentation updated
- [ ] No new warnings introduced
```

### Review Process

1. **Automated checks**: CI/CD pipeline must pass
2. **Code review**: At least one approving review required
3. **Testing**: All tests must pass
4. **Documentation**: Docs must be updated
5. **Approval**: Maintainer approval required

---

## Commit Message Guidelines

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- **feat**: New feature
- **fix**: Bug fix
- **docs**: Documentation changes
- **style**: Code style changes (formatting)
- **refactor**: Code refactoring
- **test**: Adding or updating tests
- **chore**: Maintenance tasks

### Examples

**Good:**
```
feat(orders): add cancel_order function

Implement cancel_order function with reason tracking
and audit logging. Includes validation to prevent
canceling already filled orders.

Closes #123
```

**Bad:**
```
fixed stuff
```

---

## Project Structure

```
sql-trading-database-design/
├── schema/           # Database schema files
├── functions/        # PL/pgSQL functions
├── procedures/       # Stored procedures
├── triggers/         # Trigger definitions
├── views/            # View definitions
├── tests/
│   ├── unit/         # Unit tests
│   ├── performance/  # Performance tests
│   └── load/         # Load tests
├── queries/
│   ├── analytics/    # Analytical queries
│   ├── reports/      # Report queries
│   └── monitoring/   # Monitoring queries
├── docs/             # Documentation
└── README.md         # Main documentation
```

---

## Getting Help

- **GitHub Issues**: For bugs and feature requests
- **GitHub Discussions**: For questions and discussions
- **Documentation**: Check docs/ folder
- **Examples**: Review queries/ folder

---

## Recognition

Contributors will be recognized in:
- README.md contributors section
- CHANGELOG.md for significant contributions
- GitHub repository insights

---

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to SQL Trading Database Design! 🎉
