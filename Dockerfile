FROM python:3.11-slim
     
# Install system deps needed by some Kafka python wheels
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      librdkafka-dev \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd -m -u 1000 -s /bin/bash appuser

WORKDIR /app

# copy requirements and source
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY steam_to_kafka.py .
COPY steam_utils.py .
COPY producer_reviews.py .
COPY producer_players.py .
COPY processed_appids.txt .

# Change ownership and switch to non-root user
RUN chown -R appuser:appuser /app
USER appuser

# run unbuffered so kubectl logs shows live output
CMD ["python", "-u", "/app/steam_to_kafka.py"]
