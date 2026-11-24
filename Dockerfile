# ── Stage 1: Build React frontend ────────────────────────────────────────────
FROM node:20-alpine AS frontend-builder

WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm ci --silent
COPY frontend/ ./
RUN npm run build

# ── Stage 2: Python backend with built frontend ───────────────────────────────
FROM python:3.11-slim AS backend

WORKDIR /app

# System dependencies for PDF processing, build tools, and healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends \
    libmupdf-dev \
    libfreetype6-dev \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies using uv for fast resolution
COPY pyproject.toml requirement.txt ./
RUN pip install uv --quiet && \
    uv pip install --system \
    --extra-index-url https://download.pytorch.org/whl/cpu \
    -r requirement.txt \
    torch \
    pypdf

# Copy application code and database assets
COPY backend/ ./backend/
COPY data/ ./data/

# Copy built frontend static SPA files into backend static directory
COPY --from=frontend-builder /app/frontend/dist ./frontend/dist

# Ensure data directories exist
RUN mkdir -p /app/data/pdf_files

# Expose port 8000
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/health')"

# Run FastAPI application server with Uvicorn
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
