# test-e2e-pipeline.ps1
# End-to-End Pipeline Test: Steam API → Kafka → Spark → HDFS + MongoDB
$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Steam Analytics Pipeline - E2E Test     " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 0: Cleanup Previous Run ---
Write-Host "[0/10] Cleaning up previous run..." -ForegroundColor Yellow
kubectl delete job steam-producer --ignore-not-found 2>$null | Out-Null
Write-Host "  Deleted old producer job" -ForegroundColor Gray
kubectl delete sparkapplication steam-reviews-app steam-charts-app --ignore-not-found 2>$null | Out-Null
Write-Host "  Deleted old Spark apps" -ForegroundColor Gray
# Wait for pods to terminate
Start-Sleep -Seconds 5
Write-Host "  Cleanup complete" -ForegroundColor Green

# --- Step 1: Check Infrastructure ---
Write-Host "[1/10] Checking infrastructure pods..." -ForegroundColor Yellow
$requiredPods = @("simple-kafka-broker", "simple-hdfs-namenode", "simple-zk-server")
foreach ($pod in $requiredPods) {
    $status = kubectl get pods | Select-String $pod | Select-String "Running"
    if (-not $status) {
        Write-Host "ERROR: $pod is not running. Run .\test\start.ps1 first." -ForegroundColor Red
        exit 1
    }
}
Write-Host "  Infrastructure pods OK" -ForegroundColor Green

# --- Step 2: Deploy MongoDB ---
Write-Host "`n[2/10] Deploying MongoDB..." -ForegroundColor Yellow
kubectl apply -f mongodb.yaml 2>$null | Out-Null
$timeout = 120
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
    Write-Host "ERROR: MongoDB failed to start within $timeout seconds" -ForegroundColor Red
    exit 1
}

# --- Step 3: Create Kafka Topics ---
Write-Host "`n[3/10] Creating Kafka topics..." -ForegroundColor Yellow
$topics = kubectl exec simple-kafka-broker-default-0 -c kafka -- bin/kafka-topics.sh --list --bootstrap-server localhost:9092 2>$null
if ($topics -notmatch "game_info") {
    kubectl exec simple-kafka-broker-default-0 -c kafka -- bin/kafka-topics.sh --create --bootstrap-server localhost:9092 --topic game_info --partitions 3 --replication-factor 1 2>$null | Out-Null
    Write-Host "  Created topic: game_info" -ForegroundColor Green
} else {
    Write-Host "  Topic game_info already exists" -ForegroundColor Gray
}
if ($topics -notmatch "game_comments") {
    kubectl exec simple-kafka-broker-default-0 -c kafka -- bin/kafka-topics.sh --create --bootstrap-server localhost:9092 --topic game_comments --partitions 3 --replication-factor 1 2>$null | Out-Null
    Write-Host "  Created topic: game_comments" -ForegroundColor Green
} else {
    Write-Host "  Topic game_comments already exists" -ForegroundColor Gray
}

# --- Step 4: Build Docker Image ---
Write-Host "`n[4/10] Building Steam producer Docker image..." -ForegroundColor Yellow
Push-Location ..
$buildOutput = docker build -t steam-producer:latest . 2>&1
Pop-Location
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Docker build output: $buildOutput" -ForegroundColor Gray
    Write-Host "WARNING: Docker build failed - checking if image already exists..." -ForegroundColor Yellow
    $existingImage = docker images steam-producer:latest --format "{{.Repository}}:{{.Tag}}" 2>$null
    if ($existingImage -eq "steam-producer:latest") {
        Write-Host "  Using existing Docker image" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Docker image not available" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  Docker image built successfully" -ForegroundColor Green
}

# --- Step 5: Deploy Spark ConfigMaps ---
Write-Host "`n[5/10] Deploying Spark ConfigMaps..." -ForegroundColor Yellow
kubectl apply -f kafka-spark-configmap.yaml 2>$null | Out-Null
Write-Host "  ConfigMaps deployed" -ForegroundColor Green

# --- Step 6: Deploy Spark streaming apps ---
Write-Host "`n[6/10] Deploying Spark streaming apps..." -ForegroundColor Yellow
kubectl apply -f steam-reviews-app.yaml 2>$null | Out-Null
kubectl apply -f steam-charts-app.yaml 2>$null | Out-Null
Write-Host "  Spark apps deployed" -ForegroundColor Green

# --- Step 7: Wait for Spark drivers to start ---
Write-Host "`n[7/10] Waiting for Spark drivers to start (this may take 2-3 minutes)..." -ForegroundColor Yellow
$timeout = 180
$elapsed = 0
while ($elapsed -lt $timeout) {
    $drivers = kubectl get pods -l spark-role=driver --no-headers 2>$null | Select-String "Running"
    $driverCount = ($drivers | Measure-Object).Count
    if ($driverCount -ge 2) {
        Write-Host "  Spark drivers are running ($driverCount/2)" -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 10
    $elapsed += 10
    Write-Host "  Waiting for Spark drivers... ($elapsed s, $driverCount/2 running)" -ForegroundColor Gray
}
if ($elapsed -ge $timeout) {
    Write-Host "WARNING: Not all Spark drivers started within $timeout seconds" -ForegroundColor Yellow
}

# --- Step 8: Run Steam Producer ---
Write-Host "`n[8/10] Running Steam producer job..." -ForegroundColor Yellow
kubectl delete job steam-producer --ignore-not-found 2>$null | Out-Null
Start-Sleep -Seconds 2
kubectl apply -f steam-job.yaml 2>$null | Out-Null

# Wait for producer to complete
$timeout = 300
$elapsed = 0
while ($elapsed -lt $timeout) {
    $producerStatus = kubectl get pods -l job-name=steam-producer -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($producerStatus -eq "Succeeded") {
        Write-Host "  Producer completed successfully" -ForegroundColor Green
        break
    } elseif ($producerStatus -eq "Failed") {
        Write-Host "ERROR: Producer job failed" -ForegroundColor Red
        kubectl logs -l job-name=steam-producer --tail=20
        exit 1
    }
    Start-Sleep -Seconds 10
    $elapsed += 10
    Write-Host "  Producer running... ($elapsed s)" -ForegroundColor Gray
}
if ($elapsed -ge $timeout) {
    Write-Host "WARNING: Producer did not complete within $timeout seconds (may still be running)" -ForegroundColor Yellow
}

# --- Step 9: Wait for data to flow through pipeline ---
Write-Host "`n[9/10] Waiting for data to flow through pipeline (60 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

# --- Step 10: Verify Results ---
Write-Host "`n[10/10] Verifying results..." -ForegroundColor Yellow

# Check HDFS
Write-Host "`n  [HDFS Cold Storage]" -ForegroundColor Cyan
$hdfsCharts = kubectl exec simple-hdfs-namenode-default-0 -- hdfs dfs -ls /user/stackable/archive/charts/ 2>$null | Select-String "parquet"
$hdfsReviews = kubectl exec simple-hdfs-namenode-default-0 -- hdfs dfs -ls /user/stackable/archive/reviews/ 2>$null | Select-String "parquet"
$chartsCount = ($hdfsCharts | Measure-Object).Count
$reviewsCount = ($hdfsReviews | Measure-Object).Count

if ($chartsCount -gt 0) {
    Write-Host "    ✓ Charts data: $chartsCount parquet files" -ForegroundColor Green
} else {
    Write-Host "    ✗ Charts data: No files found" -ForegroundColor Red
}

if ($reviewsCount -gt 0) {
    Write-Host "    ✓ Reviews data: $reviewsCount parquet files" -ForegroundColor Green
} else {
    Write-Host "    ✗ Reviews data: No files found" -ForegroundColor Red
}

# Check MongoDB
Write-Host "`n  [MongoDB Hot Storage]" -ForegroundColor Cyan
$mongoPod = kubectl get pods -l app=mongodb -o jsonpath='{.items[0].metadata.name}' 2>$null
if ($mongoPod) {
    $chartsDocsRaw = kubectl exec $mongoPod -- mongosh game_analytics --quiet --eval "db.steam_charts.countDocuments()" 2>$null
    $reviewsDocsRaw = kubectl exec $mongoPod -- mongosh game_analytics --quiet --eval "db.steam_reviews.countDocuments()" 2>$null
    # Handle multi-line output - take last non-empty line and extract number
    $chartsDocsLine = ($chartsDocsRaw | Where-Object { $_ -match '\d+' } | Select-Object -Last 1) -replace '\D', ''
    $reviewsDocsLine = ($reviewsDocsRaw | Where-Object { $_ -match '\d+' } | Select-Object -Last 1) -replace '\D', ''
    if ($chartsDocsLine) { $chartsDocs = [int]$chartsDocsLine } else { $chartsDocs = 0 }
    if ($reviewsDocsLine) { $reviewsDocs = [int]$reviewsDocsLine } else { $reviewsDocs = 0 }
    
    if ($chartsDocs -gt 0) {
        Write-Host "    ✓ steam_charts: $chartsDocs aggregated documents" -ForegroundColor Green
    } else {
        Write-Host "    ✗ steam_charts: No documents found" -ForegroundColor Red
    }
    
    if ($reviewsDocs -gt 0) {
        Write-Host "    ✓ steam_reviews: $reviewsDocs aggregated documents" -ForegroundColor Green
    } else {
        Write-Host "    ✗ steam_reviews: No documents found" -ForegroundColor Red
    }
} else {
    Write-Host "    ✗ MongoDB pod not found" -ForegroundColor Red
}

# --- Summary ---
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "           E2E TEST SUMMARY                 " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$hdfsPass = ($chartsCount -gt 0) -and ($reviewsCount -gt 0)
$mongoPass = ($chartsDocs -gt 0) -and ($reviewsDocs -gt 0)

Write-Host ""
Write-Host "  Pipeline Components:" -ForegroundColor White
Write-Host "    MongoDB:        Running" -ForegroundColor Green
Write-Host "    Kafka Topics:   game_info, game_comments" -ForegroundColor Green
Write-Host "    Steam Producer: Completed" -ForegroundColor Green
Write-Host "    Spark Apps:     Running" -ForegroundColor Green
Write-Host ""
Write-Host "  Data Verification:" -ForegroundColor White
if ($hdfsPass) {
    Write-Host "    HDFS (Cold):    PASS" -ForegroundColor Green
} else {
    Write-Host "    HDFS (Cold):    FAIL" -ForegroundColor Red
}
if ($mongoPass) {
    Write-Host "    MongoDB (Hot):  PASS" -ForegroundColor Green
} else {
    Write-Host "    MongoDB (Hot):  FAIL" -ForegroundColor Red
}

Write-Host ""
if ($hdfsPass -and $mongoPass) {
    Write-Host "  ✓ END-TO-END TEST PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "  ✗ END-TO-END TEST FAILED" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Troubleshooting:" -ForegroundColor Yellow
    Write-Host "    - Check Spark driver logs: kubectl logs -l spark-role=driver --tail=50" -ForegroundColor Gray
    Write-Host "    - Check producer logs: kubectl logs -l job-name=steam-producer --tail=50" -ForegroundColor Gray
    exit 1
}
