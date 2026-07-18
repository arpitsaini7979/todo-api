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
COPY --from=builder /root/.local /home/appuser/.local

# Copy application source code
COPY . .

# Make sure the non-root user owns the app files
RUN chown -R appuser:appuser /app

USER appuser

# Add the user-installed packages to PATH
ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    FLASK_ENV=production

EXPOSE 3000

# gunicorn is the production WSGI server; "app:app" means "in app.py, use the object named app"
CMD ["gunicorn", "--bind", "0.0.0.0:3000", "app:app"]
