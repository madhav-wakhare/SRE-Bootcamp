# Student CRUD REST API

This repository contains a simple Flask-based REST API for managing students. It exposes endpoints for creating, listing, retrieving, updating, and deleting student records.

## Features
- CRUD operations for students
- Versioned API routes under `/api/v1/students`
- Health check endpoint at `/healthcheck`
- SQLite database with SQLAlchemy
- Environment-based database configuration
- Unit tests for the main API flows

## Beginner-friendly concepts used
- Flask: a small Python web framework for building web apps.
- Route: a URL that your app responds to, such as `/api/v1/students`.
- HTTP methods: `GET` reads data, `POST` creates data, `PUT` updates data, and `DELETE` removes data.
- JSON: a common format for sending data between a client and a server.
- SQLAlchemy: a Python library that helps you work with databases using Python objects.
- Environment variables: values passed into the app from the shell, such as `DATABASE_URL`.
- pytest: a Python testing tool used to verify your app works correctly.

## Local setup

1. Create and activate a virtual environment:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   ```
2. Install dependencies:
   ```bash
   make install
   ```
3. Configure environment variables. Create a `.env` file at the root of the project:
   ```env
   DATABASE_URL=postgresql://postgres:postgres@localhost:5432/students_db
   PORT=5000
   ```
   *(The application automatically loads variables from `.env` at startup using `python-dotenv`.)*
4. Run database migrations/schema setup:
   ```bash
   make migrate
   ```
   This creates the required tables in the configured database (e.g. PostgreSQL).
5. Start the application:
   ```bash
   make run
   ```

The API will be available at `http://127.0.0.1:5000` (or whatever `PORT` you configured).

## Environment variables
- `DATABASE_URL`: Connection URL for the database (e.g., `postgresql://postgres:postgres@localhost:5432/students_db`).
- `PORT`: Port number on which the web server binds (defaults to `5000`).

## Docker setup

1. Build the Docker image (tagged with semver, defaults to version `1.0.0`):
   ```bash
   make docker-build
   ```
2. Run the Docker container (injects environment variables dynamically using the `.env` file):
   ```bash
   make docker-run
   ```
   *To run the container manually and pass variables directly:*
   ```bash
   docker run --rm -p 5000:5000 -e DATABASE_URL="postgresql://username:password@host:port/dbname" -e PORT="5000" sre-student-api:1.0.0
   ```

## Testing
```bash
make test
```

## API endpoints
- `GET /healthcheck`
- `POST /api/v1/students`
- `GET /api/v1/students`
- `GET /api/v1/students/<id>`
- `PUT /api/v1/students/<id>`
- `DELETE /api/v1/students/<id>`
