import os

class Config:
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    @staticmethod
    def get_database_uri():
        db_url = os.getenv("DATABASE_URL")
        
        # Automatically fallback host.docker.internal to localhost if running outside Docker
        if db_url and "host.docker.internal" in db_url:
            if not os.path.exists("/.dockerenv"):
                db_url = db_url.replace("host.docker.internal", "127.0.0.1")
        
        return db_url or "sqlite:///students.db"
