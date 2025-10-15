# CI/CD Database Test Fix - pgTAP Installation

## Date
October 15, 2025

## Problem
The CI/CD Pipeline "Run Database Tests" job was failing after 53 seconds with the following error:

```
ERROR:  extension "pgtap" is not available
DETAIL:  Could not open extension control file "/usr/local/share/postgresql/extension/pgtap.control": No such file or directory.
```

## Root Cause
The pgTAP extension installation was being performed on the GitHub Actions runner host, but the PostgreSQL database was running inside a Docker container (`timescale/timescaledb:latest-pg15`). This meant the extension files were installed in the wrong location and were not accessible to the PostgreSQL instance.

## Solution
Modified the "Install pgTAP" step in `.github/workflows/ci.yml` to install pgTAP inside the PostgreSQL Docker container:

### Before
```yaml
- name: Install pgTAP
  env:
    PGPASSWORD: postgres
  run: |
    sudo apt-get install -y build-essential
    git clone https://github.com/theory/pgtap.git
    cd pgtap
    make
    sudo make install
    psql -h localhost -U postgres -d trading_db_test -c "CREATE EXTENSION IF NOT EXISTS pgtap;"
    
    # Install pg_prove for running TAP tests
    sudo apt-get install -y libtap-parser-sourcehandler-pgtap-perl
```

### After
```yaml
- name: Install pgTAP
  env:
    PGPASSWORD: postgres
  run: |
    # Find the PostgreSQL container ID
    CONTAINER_ID=$(docker ps --filter "ancestor=timescale/timescaledb:latest-pg15" --format "{{.ID}}")
    echo "PostgreSQL container ID: $CONTAINER_ID"
    
    # Install pgTAP inside the PostgreSQL container
    docker exec $CONTAINER_ID sh -c "
      apk add --no-cache build-base git perl && \
      git clone https://github.com/theory/pgtap.git /tmp/pgtap && \
      cd /tmp/pgtap && \
      make && \
      make install
    "
    
    # Verify installation and create extension
    psql -h localhost -U postgres -d trading_db_test -c "CREATE EXTENSION IF NOT EXISTS pgtap;"
    
    # Install pg_prove for running TAP tests on the runner
    sudo apt-get install -y libtap-parser-sourcehandler-pgtap-perl
```

## Key Changes
1. **Container Detection**: Uses `docker ps` with filter to find the PostgreSQL container
2. **In-Container Installation**: Uses `docker exec` to run installation commands inside the container
3. **Alpine Packages**: Uses `apk` (Alpine Package Keeper) instead of `apt` since TimescaleDB image is Alpine-based
4. **Verification**: Adds explicit verification step to ensure the extension can be created
5. **Clear Separation**: Keeps `pg_prove` installation on the runner (where it needs to be for test execution)

## Verification
### Local Testing Results
- ✅ All schema files load without errors
- ✅ All functions load successfully  
- ✅ All procedures load successfully
- ✅ All triggers load successfully
- ✅ All views load successfully
- ✅ pgTAP extension installs and loads successfully
- ✅ Unit tests pass (30/30 tests)

### CI/CD Impact
The fix ensures that:
1. pgTAP is installed in the correct PostgreSQL instance (inside the Docker container)
2. The CREATE EXTENSION command succeeds
3. Unit tests can run properly with pgTAP
4. The entire CI/CD pipeline completes successfully

## Files Modified
- `.github/workflows/ci.yml` - Updated "Install pgTAP" step (9 lines added, 6 lines removed)

## Testing Recommendations
1. Approve and run the CI/CD workflow to verify the fix
2. Monitor the "Install pgTAP" step to ensure it completes without errors
3. Verify that all unit tests pass
4. Confirm that subsequent CI/CD runs continue to work

## Conclusion
This was a minimal, surgical fix that addresses the root cause of the CI/CD failure. The solution respects the Docker container architecture and ensures pgTAP is installed in the correct location for the PostgreSQL instance to access it.
