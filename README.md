# Steam Game Analytics Pipeline

A real-time big data pipeline for Steam game analytics using **Kappa Architecture**.

## Architecture (Kappa)

This pipeline follows the **Kappa Architecture** pattern - a single streaming path that writes to both hot (MongoDB) and cold (HDFS) storage.

```
┌──────────────┐    ┌─────────────────────┐    ┌─────────────────────────────┐
│  Steam API   │───▶│  steam_to_kafka.py  │───▶│  Kafka Topics               │
│  - appdetails│    │  (Producer)         │    │  - game_info (metadata)     │
│  - appreviews│    └─────────────────────┘    │  - game_comments (reviews)  │
│  - search    │                               └──────────────┬──────────────┘
└──────────────┘                                              │
                                           ┌──────────────────┴──────────────────┐
                                           ▼                                     ▼
                              ┌────────────────────────┐          ┌────────────────────────┐
                              │  steam-charts-app      │          │  steam-reviews-app     │
                              │  (Spark Streaming)     │          │  (Spark Streaming)     │
                              └───────────┬────────────┘          └───────────┬────────────┘
                                          │                                   │
                           ┌──────────────┴──────────────┐     ┌──────────────┴──────────────┐
                           ▼                             ▼     ▼                             ▼
                    ┌────────────┐              ┌─────────────────┐              ┌────────────┐
                    │ HDFS       │              │ MongoDB         │              │ HDFS       │
                    │ /archive/  │              │ game_analytics  │              │ /archive/  │
                    │ charts/    │              │ (hot storage)   │              │ reviews/   │
                    └────────────┘              └─────────────────┘              └────────────┘
                    (Cold Storage)              (Hot Storage)                    (Cold Storage)
```

### Why Kappa over Lambda?

| Factor | Our Choice | Reasoning |
|--------|------------|-----------|
| Data Source | Real-time Steam API | Single streaming source |
| Processing Logic | Identical for hot/cold | No need for separate batch logic |
| Reprocessing | Via Kafka replay | Kafka retention handles historical data |
| Complexity | Lower | Single codebase to maintain |

## Technology Stack

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| Orchestration | Kubernetes + Stackable | 25.7.0 | Container orchestration |
| Coordination | Apache Zookeeper | 3.9.3 | Distributed coordination |
| Messaging | Apache Kafka | 3.9.1 | Stream buffering |
| Processing | Apache Spark | 3.5.6 | Structured Streaming |
| Cold Storage | Apache HDFS | 3.4.1 | Parquet archival |
| Hot Storage | MongoDB | 7.0 | Real-time analytics |

## Installation (Windows)

### Prerequisites
1. **Docker Desktop** with Kubernetes enabled
   - Download from [docker.com](https://www.docker.com/products/docker-desktop/)
   - Enable Kubernetes in Settings > Kubernetes
   - Verify: `kubectl cluster-info`

2. **Helm v3.19.0+**
   - Download from [helm.sh](https://github.com/helm/helm/releases)
   - Add to PATH environment variable
   - Verify: `helm version`

### Install Stackable Operators
```powershell
helm install --wait commons-operator oci://oci.stackable.tech/sdp-charts/commons-operator --version 25.7.0
helm install --wait secret-operator oci://oci.stackable.tech/sdp-charts/secret-operator --version 25.7.0
helm install --wait listener-operator oci://oci.stackable.tech/sdp-charts/listener-operator --version 25.7.0
helm install --wait zookeeper-operator oci://oci.stackable.tech/sdp-charts/zookeeper-operator --version 25.7.0
helm install --wait kafka-operator oci://oci.stackable.tech/sdp-charts/kafka-operator --version 25.7.0
helm install --wait hdfs-operator oci://oci.stackable.tech/sdp-charts/hdfs-operator --version 25.7.0
helm install --wait spark-k8s-operator oci://oci.stackable.tech/sdp-charts/spark-k8s-operator --version 25.7.0
```

## Quick Start

### 1. Deploy Infrastructure
```powershell
.\test\start.ps1   # Deploys Zookeeper, Kafka, HDFS (~3-5 minutes)
```

### 2. Run End-to-End Pipeline Test (Recommended)
```powershell
.\test\test-e2e-pipeline.ps1   # Full pipeline test (~5-10 minutes)
```

This single command will:
- Verify infrastructure (Zookeeper, Kafka, HDFS)
- Deploy MongoDB (hot storage)
- Create Kafka topics (`game_info`, `game_comments`)
- Build Docker image for producer
- Deploy Spark streaming apps
- Run Steam producer (fetches live data from Steam API)
- Verify data in HDFS and MongoDB

### 3. Run Individual Component Tests (For Debugging)
```powershell
.\test\test-hdfs.ps1             # Test HDFS read/write (~2 min)
.\test\test-kafka.ps1            # Test Kafka produce/consume (~2 min)
.\test\test-spark-kafka-app.ps1  # Test Spark streaming (~3 min)
.\test\test-all.ps1              # Run all individual tests
```

### 4. Manual Pipeline Deployment
```powershell
# 1. Deploy MongoDB
kubectl apply -f mongodb.yaml

# 2. Create Kafka topics
kubectl exec -it simple-kafka-broker-default-0 -c kafka -- bin/kafka-topics.sh `
  --create --bootstrap-server localhost:9092 --topic game_info --partitions 3 --replication-factor 1
kubectl exec -it simple-kafka-broker-default-0 -c kafka -- bin/kafka-topics.sh `
  --create --bootstrap-server localhost:9092 --topic game_comments --partitions 3 --replication-factor 1

# 3. Build and run Steam producer
docker build -t steam-producer:latest .
kubectl apply -f steam-job.yaml

# 4. Deploy Spark streaming apps
kubectl apply -f kafka-spark-configmap.yaml
kubectl apply -f steam-charts-app.yaml
kubectl apply -f steam-reviews-app.yaml
```

### 5. Monitor & Verify
```powershell
# Check all pods
kubectl get pods

# Watch pods in real-time
kubectl get pods -w

# View Spark driver logs
kubectl logs -l spark-role=driver --tail=100 -f

# View producer logs
kubectl logs -l job-name=steam-producer --tail=50

# Check HDFS data
kubectl exec simple-hdfs-namenode-default-0 -- hdfs dfs -ls /user/stackable/archive/

# Access MongoDB
kubectl port-forward svc/mongodb 27017:27017
# Then: mongosh mongodb://localhost:27017/game_analytics
```

## Project Structure
```
├── zookeeper.yaml              # Zookeeper cluster (coordination)
├── kafka.yaml                  # Kafka cluster (messaging)
├── kafka-znode.yaml            # Kafka Zookeeper node
├── hdfs.yaml                   # HDFS cluster (HA mode, cold storage)
├── hdfs-znode.yaml             # HDFS Zookeeper node
├── webhdfs.yaml                # WebHDFS helper pod (testing)
├── mongodb.yaml                # MongoDB (hot storage)
├── steam-job.yaml              # Steam producer Job + ConfigMap
├── kafka-spark-configmap.yaml  # Spark processing scripts
├── kafka-test-configmap.yaml   # Spark test script
├── kafka-test-app.yaml         # Spark test application
├── steam-charts-app.yaml       # Spark: game_info → HDFS + MongoDB
├── steam-reviews-app.yaml      # Spark: game_comments → HDFS + MongoDB
├── Dockerfile                  # Producer container image
├── .dockerignore               # Docker build exclusions
├── steam_to_kafka.py           # Steam API → Kafka producer
├── requirements.txt            # Python dependencies
├── inputs/                     # Sample data (reference)
│   ├── charts/
│   └── reviews/
└── test/                       # Test scripts
    ├── start.ps1               # Deploy infrastructure
    ├── test-hdfs.ps1           # HDFS connectivity test
    ├── test-kafka.ps1          # Kafka produce/consume test
    ├── test-spark-kafka-app.ps1
    └── test-e2e-pipeline.ps1   # Full E2E test
```

## Testing

### End-to-End Pipeline Test (Recommended)
```powershell
.\test\test-e2e-pipeline.ps1
```

This comprehensive test validates the entire data pipeline:
1. Infrastructure check (Zookeeper, Kafka, HDFS)
2. MongoDB deployment
3. Kafka topic creation
4. Docker image build
5. Spark streaming apps deployment
6. Steam producer execution
7. Data verification in HDFS and MongoDB

### Component Tests (For Debugging)
```powershell
.\test\test-hdfs.ps1             # HDFS read/write test
.\test\test-kafka.ps1            # Kafka produce/consume test
.\test\test-spark-kafka-app.ps1  # Spark streaming test
.\test\test-all.ps1              # All component tests
```

## Data Flow

### Kafka Topics
| Topic | Description | Schema |
|-------|-------------|--------|
| `game_info` | Game metadata | name, appid, type, developers (JSON), genres (JSON), price, etc. |
| `game_comments` | Game reviews | app_id, review_id, author, recommended, votes_up, review text, etc. |

### Storage Locations
| Type | Location | Format | Purpose |
|------|----------|--------|---------|
| Cold | `/user/stackable/archive/charts/` | Parquet | Game info archival |
| Cold | `/user/stackable/archive/reviews/` | Parquet | Reviews archival |
| Hot | `game_analytics.steam_charts` | MongoDB | Game type aggregations |
| Hot | `game_analytics.steam_reviews` | MongoDB | Sentiment aggregations |

## Configuration

### Environment Variables (Producer)
| Variable | Default | Description |
|----------|---------|-------------|
| `BOOTSTRAP_SERVERS` | `localhost:9092` | Kafka broker address |
| `TOPIC_GAME_INFO` | `game_info` | Topic for game metadata |
| `TOPIC_GAME_COMMENTS` | `game_comments` | Topic for reviews |
| `FILTERS` | `topsellers` | Steam search filters |
| `PAGE_LIST` | `1` | Pages to fetch |

### MongoDB Authentication (Production)
```powershell
# Create secret for MongoDB auth
kubectl create secret generic mongodb-secret `
  --from-literal=username=admin `
  --from-literal=password=<your-password>

# Update Spark apps' MongoDB URI to include credentials
# mongodb://admin:<password>@mongodb.default.svc.cluster.local:27017/...
```

## Troubleshooting

### Pods not starting
```powershell
kubectl get pods                    # Check status
kubectl describe pod <pod-name>     # Detailed info
kubectl logs <pod-name>             # View logs
```

### Kafka issues
```powershell
# List topics
kubectl exec simple-kafka-broker-default-0 -c kafka -- `
  bin/kafka-topics.sh --list --bootstrap-server localhost:9092

# Check consumer groups
kubectl exec simple-kafka-broker-default-0 -c kafka -- `
  bin/kafka-consumer-groups.sh --list --bootstrap-server localhost:9092
```

### HDFS issues
```powershell
# Check cluster health
kubectl exec simple-hdfs-namenode-default-0 -- hdfs dfsadmin -report

# List files
kubectl exec simple-hdfs-namenode-default-0 -- hdfs dfs -ls -R /user/stackable/
```

### Spark issues
```powershell
# Check driver logs
kubectl logs -l spark-role=driver --tail=100

# Check executor logs
kubectl logs -l spark-role=executor --tail=50
```

### Full Reset
```powershell
.\test\start.ps1    # This will teardown and redeploy infrastructure
```

## License
MIT
