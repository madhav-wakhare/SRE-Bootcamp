# Student CRUD REST API

This repository contains a simple Flask-based REST API for managing students. It exposes endpoints for creating, listing, retrieving, updating, and deleting student records.

## Features
- CRUD operations for students
- Versioned API routes under `/api/v1/students`
- Health check endpoint at `/healthcheck`
- PostgreSQL database with SQLAlchemy (SQLite fallback for unit testing)
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

## Prerequisites & Installation

To run this application locally, you need `docker` (with docker compose) and `make` installed.

If you do not have these tools installed, you can use the following helper functions to install them based on your OS:

### macOS (using Homebrew)
```bash
# Function to install prerequisites on macOS
install_macos_prereqs() {
  echo "Installing Homebrew if not present..."
  command -v brew >/dev/null 2>&1 || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  
  echo "Installing Make..."
  xcode-select --install || true
  
  echo "Installing Docker..."
  brew install --cask docker
  
  echo "Prerequisites installation complete. Please ensure Docker is running."
}
```

### Linux (Ubuntu/Debian)
```bash
# Function to install prerequisites on Ubuntu/Debian
install_linux_prereqs() {
  echo "Updating package lists..."
  sudo apt-get update
  
  echo "Installing Make and build tools..."
  sudo apt-get install -y build-essential
  
  echo "Installing Docker..."
  sudo apt-get install -y docker.io docker-compose-v2
  
  echo "Adding user to docker group..."
  sudo usermod -aG docker $USER
  
  echo "Prerequisites installation complete. Please log out and log back in."
}
```

---

## One-Click Local Development Setup

We support a simplified, containerized one-click local development setup using Docker Compose and `make`.

### Docker Network Setup
Ensure that the external network `sre-network` exists before running the compose stack:
```bash
docker network create sre-network
```

### Make Targets and Order of Execution
The Makefile contains targets to build, migrate, and run the services. 

1. **Start the Database Container**:
   Starts the PostgreSQL container in the background.
   ```bash
   make db-start
   ```

2. **Run DB Migrations inside Docker**:
   Applies DML schema migrations inside the container.
   ```bash
   make migrate-server
   ```

3. **Build the REST API Docker Image**:
   Builds the Docker image for the Flask application.
   ```bash
   make docker-build
   ```

4. **One-Click Run (REST API & DB)**:
   You have two choices depending on where you want the REST API application to run:

   - **Option A: Run REST API inside Docker Compose**:
     Starts/verifies the database container, checks/applies migrations in the container, and starts the REST API service inside Docker Compose.
     ```bash
     make docker-run
     ```

   - **Option B: Run REST API locally (on Host)**:
     Starts/verifies the database container, checks/applies migrations locally, and starts the REST API service locally on your host machine.
     ```bash
     make run-server
     ```


---

## Manual Local Setup (Without Docker)

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
4. Run database migrations/schema setup locally:
   ```bash
   make migrate
   ```
5. Start the application locally:
   ```bash
   make run
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

---

## Continuous Integration (CI) Pipeline

A GitHub Actions workflow is defined in `.github/workflows/ci.yml` that automates build, test, lint, and packaging tasks on a **self-hosted runner**.

### Pipeline Stages
1. **Build API**: Runs `make install` to install dependencies in the repository workspace.
2. **Perform Code Linting**: Runs `make lint` (Hadolint check for the `Dockerfile`).
3. **Run Tests**: Runs `make test` (pytest unit test suite).
4. **Docker Login**: Logs into Docker Hub using secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.
5. **Docker Build and Push**: Builds the Docker image (using `make docker-build`) and pushes it to Docker Hub (`<dockerhub-username>/sre-student-api:<7-char-commit-hash>`).


### Triggers
* **Automatic**: Triggers on pushes or pull requests affecting production code/configuration files (`app.py`, `migrations/`, `tests/`, `requirements.txt`, `Dockerfile`, `Makefile`).
* **Manual**: Allows manual workflow runs from the GitHub Actions tab (`workflow_dispatch`).


### Setting Up a Self-Hosted Runner
To execute the pipeline, configure a self-hosted runner on your local machine:
1. Navigate to your GitHub repository -> **Settings** -> **Actions** -> **Runners** -> **New self-hosted runner**.
2. Select your OS (macOS/Linux) and architecture.
3. Follow the provided commands to download, configure, and launch the runner:
   ```bash
   # Example Configuration (Replace with token from GitHub Settings)
   ./config.sh --url https://github.com/<owner>/<repo> --token <registration-token>
   
   # Run the worker
   ./run.sh
   ```

---

## Kubernetes (K8s) Deployment

Our application stack is designed for production deployment on Kubernetes using Vault for secret management and External Secrets Operator (ESO) for dynamic secret injection.

### Architecture & Directory Structure
- `hashicorp-vault/`: Contains `h-vault.yml` deploying HashiCorp Vault in `vault-ns`.
- `k8s/es-operator/`: Contains `cluster-secret-store.yml` and `external-secret.yml` for ESO integration.
- `k8s/student-api/`: Contains `db.yml` (PostgreSQL StatefulSet & Secret) and `app.yml` (API Deployment, initContainer migrations, Service, HPA).

### Deployment Order

1. **Deploy HashiCorp Vault**:
   ```bash
   make vault-apply
   ```

2. **Initialize & Unseal Vault**:
   ```bash
   make vault-init
   make vault-unseal
   ```

3. **Configure Vault K8s Auth & Seed Secrets**:
   ```bash
   make vault-setup-k8s-auth
   make vault-seed
   ```

4. **Deploy External Secrets Operator Store**:
   ```bash
   kubectl apply -f k8s/es-operator/cluster-secret-store.yml
   ```

5. **Deploy Database Component**:
   ```bash
   kubectl apply -f k8s/student-api/db.yml
   ```

6. **Deploy Application Component**:
   ```bash
   kubectl apply -f k8s/student-api/app.yml
   ```

7. **Verify Deployment**:
   ```bash
   kubectl get pods -n student-api
   curl http://<node-ip>:30080/healthcheck
   ```


