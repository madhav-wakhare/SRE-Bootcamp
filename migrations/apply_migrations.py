import os
import sys

# Add the parent directory of this file to the Python path to allow importing the app module
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app import create_app, db


def apply_migrations():
    """
    Run database migrations to ensure the necessary schema/tables exist.
    This script is database-agnostic because it uses SQLAlchemy's db.create_all() under the
    application context, meaning it will automatically match whatever database type
    (PostgreSQL, MySQL, SQLite, etc.) is configured in the environment's DATABASE_URL.
    """
    # Create the Flask application instance
    app = create_app()

    # Run table creation under the Flask app context
    with app.app_context():
        # Retrieve the database URI config
        db_uri = app.config.get("SQLALCHEMY_DATABASE_URI", "")
        
        # Mask the connection credentials in standard log output for security
        masked_uri = db_uri
        if "@" in db_uri:
            try:
                prefix, rest = db_uri.split("@", 1)
                scheme = prefix.split("://", 1)[0]
                masked_uri = f"{scheme}://***@{rest}"
            except Exception:
                masked_uri = "database-connection-string"
                
        print(f"Applying database schema migrations against: {masked_uri}")
        # Use SQLAlchemy metadata reflection to create the student table
        db.create_all()
        print("Database schema migration completed successfully.")


# If this script is run directly, apply the migrations
if __name__ == "__main__":
    apply_migrations()
