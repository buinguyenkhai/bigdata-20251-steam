# Running Steam Producers

This guide explains how to run the Steam data producers on the Kubernetes cluster.

## Prerequisites
- **Docker Desktop** running with Kubernetes enabled
- **Kafka** deployed and accessible (SSL/TLS)
- `producers/processed_appids.txt` populated with AppIDs to scrape

## 1. Build the Docker Image

Rebuild whenever you modify Python scripts or `processed_appids.txt`:

```powershell
docker build -t steam-producer:latest .
```

## 2. Deploy Producers (CronJobs)

All producers now run as **CronJobs** for automatic periodic execution:

```powershell
# Deploy all producer CronJobs
kubectl apply -f k8s/producers/

# Or individually:
kubectl apply -f k8s/producers/steam-cronjob.yaml         # Reviews (every 5 min)
kubectl apply -f k8s/producers/steam-cronjob-charts.yaml  # Charts (every 15 min)
```

### CronJob Schedules

| CronJob | Schedule | Script | Description |
|---------|----------|--------|-------------|
| `steam-producer-reviews` | `*/5 * * * *` | `producer_reviews.py` | Fetches game reviews |
| `steam-producer-charts` | `*/15 * * * *` | `producer_charts.py` | Fetches game metadata |

## 3. Manual Trigger (Testing)

Trigger a CronJob immediately without waiting for schedule:

```powershell
# Trigger reviews producer now
kubectl create job --from=cronjob/steam-producer-reviews reviews-manual-test

# Trigger charts producer now
kubectl create job --from=cronjob/steam-producer-charts charts-manual-test
```

## 4. Verification

```powershell
# Check CronJob status
kubectl get cronjobs

# Check recent job runs
kubectl get jobs | Select-String "steam-producer"

# View producer logs
kubectl logs -l app=steam-producer-reviews --tail=50
kubectl logs -l app=steam-producer-charts --tail=50

# Verify Kafka messages
.\test\verify-kafka-state.ps1
```

## 5. Configuration

Environment variables are set via `steam-producer-config` ConfigMap:

| Variable | Description |
|----------|-------------|
| `BOOTSTRAP_SERVERS` | Kafka broker address |
| `KAFKA_SECURITY_PROTOCOL` | `SSL` for TLS connection |
| `KAFKA_SSL_CA_LOCATION` | Path to CA certificate |

## Project Structure

```
producers/
├── producer_reviews.py      # Reviews producer script
├── producer_charts.py       # Charts/game info producer script
├── producer_players.py      # Player count producer script
├── steam_utils.py           # Shared utilities
└── processed_appids.txt     # AppIDs to process

k8s/producers/
├── steam-cronjob.yaml       # Reviews CronJob
└── steam-cronjob-charts.yaml # Charts CronJob
```
