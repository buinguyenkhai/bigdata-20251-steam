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

# Copy source code from producers/ directory
COPY producers/steam_utils.py .
COPY producers/producer_reviews.py .
COPY producers/producer_players.py .
COPY producers/producer_charts.py .
COPY producers/processed_appids.txt .

# Change ownership and switch to non-root user
RUN chown -R appuser:appuser /app
USER appuser

# Default command (can be overridden by CronJob)
CMD ["python", "-u", "producer_reviews.py"]
