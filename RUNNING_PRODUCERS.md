# Running Steam Producers

This guide explains how to run the Steam Reviews and Player Count producers on the local Kubernetes cluster.

## Prerequisites
- **Docker Desktop** running with Kubernetes enabled.
- **Kafka** deployed and accessible (SSL/TLS).
- `processed_appids.txt` populated with the AppIDs you want to scrape.

## 1. Build the Docker Image
You must rebuild the image whenever you modify the Python scripts or `processed_appids.txt`.

```powershell
docker build -t steam-producer:latest .
```

## 2. Deploying the Producers

### A. Steam Reviews Producer (Job)
This runs **once** to fetch Game Info and Reviews. It is a resource-intensive job.

```powershell
kubectl delete job steam-producer-reviews --ignore-not-found
kubectl apply -f job-reviews.yaml
```
- **Config**: `MAX_APPS_TO_PROCESS` (Default: 100), `MAX_REVIEW_PAGES` (Default: 3).
- **Check Status**: `kubectl get pods -l job-name=steam-producer-reviews`

### B. Player Count Producer (CronJob)
This runs **every 5 minutes** to fetch the current player count.

```powershell
kubectl apply -f cronjob-players.yaml
```
- **Schedule**: `*/5 * * * *` (Every 5 minutes).

## 3. Verification
Use the verification script to check if messages are reaching Kafka.

```powershell
.\test\verify-kafka-state.ps1
```
Expected output:
- **game_info**: Low count (1 per game).
- **game_comments**: High count (many reviews per game).
- **game_player_count**: Periodic count (1 per game per run).

## 4. Configuration
You can adjust the following environment variables in `job-reviews.yaml` or `cronjob-players.yaml`:

| Variable | Description | Default |
| :--- | :--- | :--- |
| `MAX_APPS_TO_PROCESS` | Max number of AppIDs to process from the text file. | 1000 |
| `MAX_REVIEW_PAGES` | Number of review pages to scrape per game (Reviews Job only). | 3 |
