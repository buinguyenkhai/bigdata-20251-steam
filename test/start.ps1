Write-Host "--- Deleting all components... ---" -ForegroundColor Cyan

# 1. Delete Spark App and Configs
kubectl delete -f kafka-test-app.yaml --ignore-not-found
kubectl delete -f kafka-test-configmap.yaml --ignore-not-found
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

# 4. Wait for Pods to Terminate
Write-Host "Waiting 30 seconds for pods to shut down..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# --- PART 2: WIPE DATA (The Fix for Zombie Data) ---
Write-Host "--- Wiping Stackable persistent data (PVCs)... ---" -ForegroundColor Red

# Delete PVCs by label selectors
kubectl delete pvc -l stackable.tech/vendor=stackable --ignore-not-found
kubectl delete pvc -l app.kubernetes.io/managed-by=stackable --ignore-not-found

# Also delete Kafka/HDFS/ZK data PVCs by name pattern (they may not have labels)
$pvcs = kubectl get pvc --no-headers -o custom-columns=":metadata.name" 2>$null
if ($pvcs) {
    $pvcs | Where-Object { $_ -match "^(data-simple-|log-dirs-simple-|listener-simple-)" } | ForEach-Object {
        kubectl delete pvc $_ --ignore-not-found 2>$null | Out-Null
    }
}

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