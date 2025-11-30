# Steam Game Analytics Pipeline

## Installation (Windows)
1. Download [Docker Desktop](https://www.docker.com/products/docker-desktop/)
2. Go to the Kubernetes tab in Docker and create cluster. Check cluster info: `kubectl cluster-info`
3. Download [Helm v3.19.0](https://github.com/helm/helm/releases)
4. Add Helm.exe path to Environment Variables
5. Install the Stackable Operators for Zookeeper + Kafka + HDFS + Spark:
```
helm install --wait commons-operator oci://oci.stackable.tech/sdp-charts/commons-operator --version 25.7.0
helm install --wait secret-operator oci://oci.stackable.tech/sdp-charts/secret-operator --version 25.7.0
helm install --wait listener-operator oci://oci.stackable.tech/sdp-charts/listener-operator --version 25.7.0
helm install --wait zookeeper-operator oci://oci.stackable.tech/sdp-charts/zookeeper-operator --version 25.7.0
helm install --wait kafka-operator oci://oci.stackable.tech/sdp-charts/kafka-operator --version 25.7.0
helm install --wait hdfs-operator oci://oci.stackable.tech/sdp-charts/hdfs-operator --version 25.7.0
helm install --wait spark-k8s-operator oci://oci.stackable.tech/sdp-charts/spark-k8s-operator --version 25.7.0
```
6. Set port forward
```
$ErrorActionPreference = "Stop"

# Deploy dependencies
kubectl apply -f zookeeper.yaml
kubectl apply -f kafka-znode.yaml
kubectl apply --server-side -f kafka.yaml

kubectl rollout status --watch --timeout=10m statefulset/simple-kafka-broker-default

# Port-forward Kafka broker in background
$pf = Start-Job { kubectl port-forward svc/simple-kafka-broker-default-bootstrap 9092:9092 > $null 2>&1 }
Start-Sleep -Seconds 3
```

7. Create two topic:
```
kubectl exec -it simple-kafka-broker-default-0 -c kafka -- `
  bin/kafka-topics.sh --create `
  --bootstrap-server localhost:9092 `
  --topic game_info `
  --partitions 3 `
  --replication-factor 1

kubectl exec -it simple-kafka-broker-default-0 -c kafka -- `
  bin/kafka-topics.sh --create `
  --bootstrap-server localhost:9092 `
  --topic game_comments `
  --partitions 3 `
  --replication-factor 1

```

8. Produce data to kafka:
```
docker build -t steam-producer:latest .
kubectl apply -f steam-job.yaml
```

9. Read data from kafka to spark
```
kubectl apply -f test.yaml
kubectl apply -f spark-test-app.yaml
```
