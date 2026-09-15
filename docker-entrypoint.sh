#!/bin/sh
# Apply migrations, then hand off to the CMD.
#
# Running migrations here rather than in the app's lifespan keeps schema
# changes to a single deliberate step, and means a failed migration stops the
# deploy instead of leaving a half-started process serving an old schema.
set -e

echo "Running database migrations..."
alembic upgrade head
echo "Migrations complete."

exec "$@"
