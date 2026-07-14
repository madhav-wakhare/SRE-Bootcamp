import os
from src.app import create_app

if __name__ == "__main__":
    app = create_app()
    # Get port from environment variable or default to 5000 to support dynamic port binding
    port = int(os.getenv("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
