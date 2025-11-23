# small, reproducible image for your Python producer
FROM python:3.11-slim

# Install system deps needed by some Kafka python wheels
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      librdkafka-dev \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# copy requirements and source
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY steam_to_kafka.py /app/steam_to_kafka.py

# run unbuffered so kubectl logs shows live output
CMD ["python", "-u", "/app/steam_to_kafka.py"]
