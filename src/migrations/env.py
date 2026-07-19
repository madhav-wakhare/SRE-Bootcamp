import os
import sys
from logging.config import fileConfig

from sqlalchemy import engine_from_config
from sqlalchemy import pool

from alembic import context

# Add workspace root directory to sys.path so Alembic can import application code
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

# Import application database metadata for Alembic autogenerate support
from src.app.models import db
from src.app.config import Config

# Alembic Config object, providing access to values in alembic.ini
config = context.config

# Interpret the config file for Python logging
if config.config_file_name:
    fileConfig(config.config_file_name)

# Set target metadata from Flask-SQLAlchemy model registry for autogenerate support
target_metadata = db.metadata

def get_url():
    """
    Retrieve database URL dynamically from environment variables (DATABASE_URL).
    Falls back to Config.get_database_uri() if DATABASE_URL is not set.
    This ensures migration commands run seamlessly across local, Docker, and CI environments.
    """
    return os.getenv("DATABASE_URL", Config.get_database_uri())


def run_migrations_offline() -> None:
    """
    Run migrations in 'offline' mode.
    This configures the context with just a URL and not an Engine,
    generating SQL scripts without requiring an active database connection.
    """
    url = get_url()
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """
    Run migrations in 'online' mode.
    Creates an Engine connected to the database and executes migrations within a transaction.
    """
    # Dynamically inject database connection URL from environment variable
    configuration = config.get_section(config.config_ini_section, {})
    configuration["sqlalchemy.url"] = get_url()

    connectable = engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection, target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
