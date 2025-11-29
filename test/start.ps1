# --- PART 1: TEARDOWN (Delete everything) ---
Write-Host "--- Deleting all components... ---" -ForegroundColor Cyan

# 1. Delete Spark App and Configs
kubectl delete -f kafka-test-app.yaml --ignore-not-found
kubectl delete -f kafka-spark-configmap.yaml --ignore-not-found

# 2. Delete Testing Pods
kubectl delete -f webhdfs.yaml --ignore-not-found
kubectl delete pod kcat-producer kcat-consumer --ignore-not-found

# 3. Delete Stackable Clusters
kubectl delete -f kafka.yaml --ignore-not-found
kubectl delete -f hdfs.yaml --ignore-not-found
kubectl delete -f kafka-znode.yaml --ignore-not-found
kubectl delete -f hdfs-znode.yaml --ignore-not-found
kubectl delete -f zookeeper.yaml --ignore-not-found

# 4. Wait for Pods to Terminate (Important!)
Write-Host "Waiting 30 seconds for pods to shut down..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# --- PART 2: WIPE DATA (The Fix for Zombie Data) ---
Write-Host "--- Wiping all persistent data (PVCs)... ---" -ForegroundColor Red

# This deletes the "poisoned" storage that caused the crash
kubectl delete pvc --all

# --- PART 3: DEPLOY FRESH (Start Again) ---
Write-Host "--- Deploying fresh clusters... ---" -ForegroundColor Green

# 1. Deploy Zookeeper First
kubectl apply -f zookeeper.yaml
Write-Host "Waiting 30 seconds for Zookeeper to initialize..."
Start-Sleep -Seconds 30

# 2. Deploy Dependencies (Znodes)
kubectl apply -f kafka-znode.yaml
kubectl apply -f hdfs-znode.yaml

# 3. Deploy Kafka and HDFS (with your reduced RAM settings)
kubectl apply -f kafka.yaml
kubectl apply -f hdfs.yaml

Write-Host "--- Restart Complete! ---" -ForegroundColor Cyan
Write-Host "Monitor the status with: kubectl get pods"