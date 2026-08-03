# ==============================================================================
# DEPRECATED: Manual Migration Script
# ------------------------------------------------------------------------------
# Manual schema creation via db.create_all() has been replaced by standard Alembic versioning.
# Migration operations are now handled via Alembic CLI commands:
#   - Apply migrations: `alembic upgrade head`
#   - Create migration: `alembic revision -m "description"`
# ==============================================================================
import sys
from alembic.config import main

if __name__ == "__main__":
    print("Executing Alembic migration upgrade...")
    sys.argv = ["alembic", "upgrade", "head"]
    main()
