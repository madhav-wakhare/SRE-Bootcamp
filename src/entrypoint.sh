#!/bin/sh
# 1. Waits for database network connectivity if DATABASE_URL is defined.
# 2. Runs Alembic database schema migrations ('alembic upgrade head').
# 3. Replaces script process with main container command via 'exec "$@"'.

set -e

# Wait for database if DATABASE_URL is configured
if [ -n "$DATABASE_URL" ]; then
  echo "Waiting for database connection to be ready..."
  python -c "
import os, socket, time, urllib.parse
db_url = os.getenv('DATABASE_URL')
url = urllib.parse.urlparse(db_url)
host = url.hostname
port = url.port or 5432
for _ in range(60):
    try:
        with socket.create_connection((host, port), timeout=2):
            print('Database connection established successfully.')
            break
    except OSError:
        time.sleep(1)
"
fi

# Apply standardized database schema migrations using Alembic
echo "Applying database migrations with Alembic..."
alembic upgrade head

# Execute the primary container command (e.g. 'python src/run.py')
exec "$@"
