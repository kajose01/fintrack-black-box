FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1
RUN useradd -r -u 10001 app
WORKDIR /app
COPY app.py .
USER app
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8080/healthz')" || exit 1
CMD ["python","app.py"]
