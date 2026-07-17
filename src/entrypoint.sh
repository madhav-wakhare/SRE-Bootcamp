#!/bin/sh
set -e

# Wait for database if DATABASE_URL is set
if [ -n "$DATABASE_URL" ]; then
  echo "Waiting for database to be ready..."
  python -c "
import os, socket, time, urllib.parse
db_url = os.getenv('DATABASE_URL')
url = urllib.parse.urlparse(db_url)
host = url.hostname
port = url.port or 5432
for _ in range(60):
    try:
        with socket.create_connection((host, port), timeout=2):
            break
    except OSError:
        time.sleep(1)
"
fi

# Run database migrations
echo "Applying migrations..."
python src/migrations/apply_migrations.py

# Execute the main container process
exec "$@"
