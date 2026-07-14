import os
import logging
from flask import Flask
from src.app.models import db
from src.app.config import Config
from src.app.routes import api_bp
from dotenv import load_dotenv

load_dotenv()

# Setup logging configuration
logger = logging.getLogger(__name__)

def setup_logging(app):
    # Configure logging to console and persistent file if LOG_FILE is defined
    log_file = os.getenv("LOG_FILE")
    handlers = [logging.StreamHandler()]
    if log_file:
        log_dir = os.path.dirname(log_file)
        if log_dir:
            os.makedirs(log_dir, exist_ok=True)
        # Touch/create the log file if it doesn't exist
        if not os.path.exists(log_file):
            with open(log_file, "a"):
                pass
        handlers.append(logging.FileHandler(log_file))
    
    logging.basicConfig(
        level=logging.INFO,
        format="[%(asctime)s] %(levelname)s in %(module)s: %(message)s",
        handlers=handlers
    )

# When you import anything from this src.app folder, Python automatically runs the code inside __init__.py first. 
# The name __init__.py tells the Python interpreter: "Treat this folder on disk as a Python package, not just a random folder."
def create_app():
    app = Flask(__name__) # Create a Flask application instance
    setup_logging(app)

    db_url = Config.get_database_uri()

    # If we are in test environment, allow using SQLite for self-contained testing
    if app.config.get("TESTING"):
        db_url = os.getenv("DATABASE_URL", "sqlite:///test.db")

    app.config["SQLALCHEMY_DATABASE_URI"] = db_url # Configure the SQLAlchemy database URI
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = Config.SQLALCHEMY_TRACK_MODIFICATIONS # Disable tracking modifications
    
    # Connects the model initilized in models.py to the flask app instance.
    # It takes the independent database engine (db) and registers it with the specific Flask application instance (app) we just built, giving the database access to the configuration settings.
    db.init_app(app) # Initialize the SQLAlchemy instance with the Flask app

    # takes those routes and officially registers them onto the live Flask application. 
    app.register_blueprint(api_bp) # Register routes blueprint

    return app
