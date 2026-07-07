FROM python:3.12-slim AS builder
# Set working directory for dependency preparation
WORKDIR /build
# Copy only requirements to leverage Docker cache layers
COPY requirements.txt .
# Install dependencies to a target directory (/install)
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

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
# Copy the application source code and migrations
COPY run.py .
COPY src/ src/
COPY migrations/ migrations/
# Create a non-root user and group with a static UID/GID (10001) for secure host file permission mapping
RUN groupadd -g 10001 sre-student && useradd -r -u 10001 -g sre-student sre-student \
    && chown -R sre-student:sre-student /app
# Switch to the non-root user
USER sre-student
# Expose default application port
EXPOSE 5000
# Set the entrypoint to run Python, allowing for flexibility in command execution
ENTRYPOINT ["python"]
# Run the application script
CMD ["run.py"]
