import os
import sys

# Add project root directory to sys.path to allow importing src module
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.app import create_app

if __name__ == "__main__":
    app = create_app()
    # Get port from environment variable or default to 5000 to support dynamic port binding
    port = int(os.getenv("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
