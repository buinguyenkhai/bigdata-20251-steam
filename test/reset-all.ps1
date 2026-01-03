# reset-all.ps1
# Full reset script - deletes all components and redeploys fresh
$rootDir = "$PSScriptRoot\.."

Write-Host "--- Deleting all components... ---" -ForegroundColor Cyan

# 1. Delete Spark Apps and Configs
kubectl delete sparkapplication steam-charts-app steam-reviews-app steam-players-app --ignore-not-found 2>$null
kubectl delete -f "$rootDir\k8s\spark-apps\kafka-spark-configmap.yaml" --ignore-not-found 2>$null

# 2. Delete Testing Pods
kubectl delete -f "$rootDir\test\kafka-test-app.yaml" --ignore-not-found 2>$null
kubectl delete -f "$rootDir\test\kafka-test-configmap.yaml" --ignore-not-found 2>$null
kubectl delete -f "$rootDir\k8s\monitoring\webhdfs.yaml" --ignore-not-found 2>$null
kubectl delete pod kcat-producer kcat-consumer --ignore-not-found 2>$null

# 3. Delete Stackable Clusters
kubectl delete -f "$rootDir\k8s\infrastructure\kafka.yaml" --ignore-not-found 2>$null
kubectl delete -f "$rootDir\k8s\infrastructure\hdfs.yaml" --ignore-not-found 2>$null
kubectl delete -f "$rootDir\k8s\infrastructure\kafka-znode.yaml" --ignore-not-found 2>$null
kubectl delete -f "$rootDir\k8s\infrastructure\hdfs-znode.yaml" --ignore-not-found 2>$null
kubectl delete -f "$rootDir\k8s\infrastructure\zookeeper.yaml" --ignore-not-found 2>$null

# 4. Wait for Pods to Terminate
Write-Host "Waiting 30 seconds for pods to shut down..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# --- PART 2: WIPE DATA (The Fix for Zombie Data) ---
Write-Host "--- Wiping Stackable persistent data (PVCs)... ---" -ForegroundColor Red

# Delete PVCs by label selectors
kubectl delete pvc -l stackable.tech/vendor=stackable --ignore-not-found 2>$null
kubectl delete pvc -l app.kubernetes.io/managed-by=stackable --ignore-not-found 2>$null

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
kubectl apply -f "$rootDir\k8s\infrastructure\zookeeper.yaml"
Write-Host "Waiting 30 seconds for Zookeeper to initialize..."
Start-Sleep -Seconds 30

# 2. Deploy Dependencies (Znodes)
kubectl apply -f "$rootDir\k8s\infrastructure\kafka-znode.yaml"
kubectl apply -f "$rootDir\k8s\infrastructure\hdfs-znode.yaml"

# 3. Deploy Kafka and HDFS
kubectl apply -f "$rootDir\k8s\infrastructure\kafka.yaml"
kubectl apply -f "$rootDir\k8s\infrastructure\hdfs.yaml"

# 4. Deploy MongoDB
kubectl apply -f "$rootDir\k8s\infrastructure\mongodb.yaml"

Write-Host "--- Restart Complete! ---" -ForegroundColor Cyan
Write-Host "Monitor the status with: kubectl get pods"