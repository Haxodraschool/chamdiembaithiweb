# =============================================================================
# GradeFlow — Dockerfile cho Render (Python 3.12 + OpenCV + PyTorch CPU)
# =============================================================================
# Build:   docker build -t gradeflow .
# Run:     docker run -p 8000:8000 -e DATABASE_URL=... gradeflow
# =============================================================================

FROM python:3.12-slim-bookworm

# ── Env ──────────────────────────────────────────────────────────────────────
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DEBIAN_FRONTEND=noninteractive \
    PORT=8000

# ── System dependencies ──────────────────────────────────────────────────────
# - libgl1, libglib2.0-0, libsm6, libxext6, libxrender1: OpenCV runtime
# - libgomp1: OpenMP cho numpy/torch
# - tesseract-ocr + tessdata-vie: OCR cho Part III (số viết tay)
# - libjpeg, libpng, libwebp: Pillow image codecs
# - curl, ca-certificates: tải dependency phụ
# - build-essential, gcc: compile psycopg2 nếu cần (dù dùng binary)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        libxrender1 \
        libgomp1 \
        libjpeg62-turbo \
        libpng16-16 \
        libwebp7 \
        tesseract-ocr \
        tesseract-ocr-vie \
        curl \
        ca-certificates \
        gcc \
        g++ \
    && rm -rf /var/lib/apt/lists/*

# ── Workdir ──────────────────────────────────────────────────────────────────
WORKDIR /app

# ── Python deps (cache layer riêng để rebuild nhanh) ─────────────────────────
COPY requirements.txt ./

# PyTorch CPU-only wheel (~150MB) — install riêng trước requirements để layer cache tốt
RUN pip install --no-cache-dir \
        --index-url https://download.pytorch.org/whl/cpu \
        torch==2.5.1

# ONNX Runtime (CNN inference nhanh hơn PyTorch CPU 2-3x)
RUN pip install --no-cache-dir onnxruntime==1.20.1

# Còn lại
RUN pip install --no-cache-dir -r requirements.txt

# ── App code ─────────────────────────────────────────────────────────────────
COPY . .

# ── Static files ─────────────────────────────────────────────────────────────
# Collect lúc build để image self-contained, runtime chỉ cần migrate
RUN python manage.py collectstatic --noinput || echo "[WARN] collectstatic deferred to runtime"

# ── Expose ───────────────────────────────────────────────────────────────────
EXPOSE 8000

# ── Entrypoint: migrate + gunicorn ───────────────────────────────────────────
CMD ["sh", "-c", "python manage.py migrate --noinput && gunicorn chamdiemtudong.wsgi --bind 0.0.0.0:${PORT} --workers 2 --threads 2 --timeout 300 --access-logfile - --error-logfile -"]
