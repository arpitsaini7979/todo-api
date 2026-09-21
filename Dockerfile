# --- Stage 1: build dependencies ---
FROM python:3.11-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# --- Stage 2: runtime image ---
FROM python:3.11-slim

WORKDIR /app

# Create a non-root user to run the app
RUN useradd --create-home appuser

# Copy installed packages from the builder stage
COPY --from=builder --chown=appuser:appuser /root/.local /home/appuser/.local

# Copy application source code (see .dockerignore for what is left out)
COPY --chown=appuser:appuser . .

USER appuser

# Add the user-installed packages to PATH
ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONUNBUFFERED=1

EXPOSE 3000

# Restarts/deploys can tell when the app is actually serving, not just started.
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:3000/health', timeout=2)"

# gunicorn is the production WSGI server; "app:app" means "in app.py, use the object named app".
# One process with several threads on purpose: prometheus-flask-exporter keeps its
# metrics in-process, so multiple worker processes would make /metrics inconsistent.
CMD ["gunicorn", "--bind", "0.0.0.0:3000", "--workers", "1", "--threads", "4", "--access-logfile", "-", "app:app"]
