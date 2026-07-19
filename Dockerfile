FROM python:3.12-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.11.27-python3.12-alpine /usr/local/bin/uv /usr/local/bin/uvx /bin/

# Set working directory for dependency preparation
WORKDIR /build
# Copy only pyproject.toml and uv.lock to leverage Docker cache layers
COPY pyproject.toml uv.lock ./
# Install dependencies using uv to a target directory (/install).
#command interface that mimics the standard pip tool (supporting options like install, compile, etc.), but executes at Rust speed.
RUN uv pip install --no-cache --system --prefix=/install -r pyproject.toml

#Final Stage
FROM python:3.12-slim
# Add metadata labels to the image
LABEL maintainer="Madhav Wakhare" \
      description="Student CRUD REST API for SRE Bootcamp" \
      version="1.0.0" \
      project="SRE-Bootcamp"
# Prevent Python from writing pyc files to disk
ENV PYTHONDONTWRITEBYTECODE=1
# Force stdout/stderr to be unbuffered (real-time logs for SRE visibility)
ENV PYTHONUNBUFFERED=1
WORKDIR /app
# Copy installed Python packages from the builder stage
COPY --from=builder /install /usr/local
# Copy alembic.ini configuration and application source code (which contains run.py, app/, migrations/ and entrypoint.sh)
COPY alembic.ini .
COPY src/ src/
# Create a non-root user and group (IDs auto-assigned)
RUN groupadd sre-student && useradd -r -g sre-student sre-student \
    && chmod +x src/entrypoint.sh \
    && chown -R sre-student:sre-student /app
# Switch to the non-root user
USER sre-student
# Expose default application port
EXPOSE 5000
# Set entrypoint to run migrations and database check on container startup
ENTRYPOINT ["src/entrypoint.sh"]
# Run the application script
CMD ["python", "src/run.py"]
