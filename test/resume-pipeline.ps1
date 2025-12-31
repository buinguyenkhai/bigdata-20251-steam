# resume-pipeline.ps1
# Resume the Steam Analytics pipeline from a stopped state
# Assumes infrastructure (ZooKeeper, Kafka, HDFS) is still running

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Steam Analytics Pipeline - RESUME       " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Check Infrastructure ---
Write-Host "[1/4] Checking infrastructure..." -ForegroundColor Yellow
$requiredPods = @("simple-kafka-broker", "simple-hdfs-namenode", "simple-zk-server")
$allRunning = $true
foreach ($pod in $requiredPods) {
    $status = kubectl get pods 2>$null | Select-String $pod | Select-String "Running"
    if (-not $status) {
        $allRunning = $false
        Write-Host "  WARNING: $pod is not running" -ForegroundColor Yellow
    }
}

if (-not $allRunning) {
    Write-Host ""
    Write-Host "Infrastructure is not running. Starting full infrastructure..." -ForegroundColor Yellow
    
    # Deploy ZooKeeper first
    Write-Host "  Starting ZooKeeper..." -ForegroundColor Gray
    kubectl apply -f zookeeper.yaml 2>$null | Out-Null
    $timeout = 120
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        $zkStatus = kubectl get pods -l app.kubernetes.io/name=zookeeper --no-headers 2>$null | Select-String "Running"
        if ($zkStatus) { break }
        Start-Sleep -Seconds 10
        $elapsed += 10
    }
    
    # Deploy Znodes
    kubectl apply -f kafka-znode.yaml 2>$null | Out-Null
    kubectl apply -f hdfs-znode.yaml 2>$null | Out-Null
    Start-Sleep -Seconds 5
    
    # Deploy Kafka and HDFS
    Write-Host "  Starting Kafka and HDFS..." -ForegroundColor Gray
    kubectl apply -f kafka.yaml 2>$null | Out-Null
    kubectl apply -f hdfs.yaml 2>$null | Out-Null
    
    $timeout = 180
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        $kafkaRunning = kubectl get pods -l app.kubernetes.io/name=kafka --no-headers 2>$null | Select-String "Running"
        $hdfsRunning = kubectl get pods -l app.kubernetes.io/name=hdfs --no-headers 2>$null | Select-String "Running"
        $kafkaCount = ($kafkaRunning | Measure-Object).Count
        $hdfsCount = ($hdfsRunning | Measure-Object).Count
        
        if ($kafkaCount -ge 1 -and $hdfsCount -ge 4) {
            Write-Host "  Kafka and HDFS are running" -ForegroundColor Green
            break
        }
        Start-Sleep -Seconds 10
        $elapsed += 10
        Write-Host "  Waiting for Kafka ($kafkaCount/1) and HDFS ($hdfsCount/4)... ($elapsed s)" -ForegroundColor Gray
    }
} else {
    Write-Host "  Infrastructure is running" -ForegroundColor Green
}

# --- Step 2: Start MongoDB ---
Write-Host "`n[2/4] Starting MongoDB..." -ForegroundColor Yellow
kubectl apply -f mongodb.yaml 2>$null | Out-Null
kubectl scale deployment mongodb --replicas=1 2>$null | Out-Null

$timeout = 60
$elapsed = 0
while ($elapsed -lt $timeout) {
    $mongoStatus = kubectl get pods -l app=mongodb -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($mongoStatus -eq "Running") {
        Write-Host "  MongoDB is running" -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 5
    $elapsed += 5
    Write-Host "  Waiting for MongoDB... ($elapsed s)" -ForegroundColor Gray
}
if ($elapsed -ge $timeout) {
    Write-Host "WARNING: MongoDB not ready within $timeout seconds" -ForegroundColor Yellow
}

# --- Step 3: Deploy ConfigMaps ---
Write-Host "`n[3/4] Deploying ConfigMaps..." -ForegroundColor Yellow
kubectl apply -f kafka-spark-configmap.yaml 2>$null | Out-Null
Write-Host "  ConfigMaps deployed" -ForegroundColor Green

# --- Step 4: Deploy Spark Apps (if not running) ---
Write-Host "`n[4/4] Checking Spark apps..." -ForegroundColor Yellow

# Temporarily set preference to Continue so "No resources found" doesn't crash the script
$ErrorActionPreference = "Continue"
$sparkApps = kubectl get sparkapplication 2>$null | Select-String "steam-"
$ErrorActionPreference = "Stop"

if (-not $sparkApps) {
    Write-Host "  Deploying Spark streaming apps..." -ForegroundColor Gray
    kubectl apply -f steam-reviews-app.yaml
    kubectl apply -f steam-charts-app.yaml
    Write-Host "  Spark apps deployed (will download dependencies on first run)" -ForegroundColor Green
} else {
    Write-Host "  Spark apps already exist" -ForegroundColor Green
}
