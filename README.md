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
6. Testing Kafka and HDFS (may take a few minutes):
```
.\test\test-kafka.ps1
.\test\test-hdfs.ps1
```