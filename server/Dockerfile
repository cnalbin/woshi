FROM python:3.13-slim
WORKDIR /app
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PHOTO_DIRECTORY=/data/photos
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && groupadd --gid 10001 qingji \
    && useradd --uid 10001 --gid 10001 --no-create-home qingji \
    && install -d -o 10001 -g 10001 /data/photos
COPY qingji ./qingji
USER 10001:10001
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8787/healthz', timeout=4).close()"]
CMD ["uvicorn", "qingji.main:app", "--host", "0.0.0.0", "--port", "8787", "--no-access-log"]
