FROM python:3.12-slim

WORKDIR /app

# 의존성 먼저 설치 (레이어 캐시 활용)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir psycopg2-binary

COPY app ./app

# 비루트 사용자로 실행 (보안)
RUN useradd -m appuser && mkdir -p /app/uploads && chown -R appuser /app
USER appuser

EXPOSE 8000

# 주의: in-memory rate limiter 때문에 워커는 1개.
# 수평 확장은 컨테이너 복제 + Redis rate limiter 전환으로.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
