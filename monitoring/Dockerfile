# Tiny stdlib-only Prometheus exporter for the Logos node API.
FROM python:3.12-slim
COPY exporter.py /usr/local/bin/exporter.py
EXPOSE 9112
ENTRYPOINT ["python3", "/usr/local/bin/exporter.py"]
