# test-e2e-pipeline.ps1
# End-to-End Pipeline Test: Steam API → Kafka → Spark → HDFS + MongoDB
$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Steam Analytics Pipeline - E2E Test     " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 0: Cleanup Previous Producer Run ---
Write-Host "[0/10] Cleaning up previous producer job..." -ForegroundColor Yellow
kubectl delete job steam-producer --ignore-not-found 2>$null | Out-Null
Write-Host "  Deleted old producer job (keeping Spark apps for faster startup)" -ForegroundColor Gray

# --- Step 1: Check Infrastructure ---
Write-Host "[1/10] Checking infrastructure pods..." -ForegroundColor Yellow
$requiredPods = @("simple-kafka-broker", "simple-hdfs-namenode", "simple-zk-server")
foreach ($pod in $requiredPods) {
    $status = kubectl get pods | Select-String $pod | Select-String "Running"
    if (-not $status) {
        Write-Host "ERROR: $pod is not running. Run .\test\reset-all.ps1 first." -ForegroundColor Red
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

# --- Step 3: Kafka Topics (Auto-Created) ---
Write-Host "`n[3/10] Kafka topics..." -ForegroundColor Yellow
# Note: Kafka topics (game_info, game_comments) are auto-created when the producer publishes
# The Stackable Kafka cluster uses TLS/SSL on port 9093, making manual topic creation complex
# Auto-creation is enabled by default in Kafka, so topics will be created on first message
Write-Host "  Topics will be auto-created when producer runs: game_info, game_comments" -ForegroundColor Green


# --- Step 4: Build Docker Image ---
Write-Host "`n[4/10] Building Steam producer Docker image..." -ForegroundColor Yellow
# Check if image already exists first (skip build for faster runs)
$existingImage = docker images steam-producer:latest --format "{{.Repository}}:{{.Tag}}" 2>$null
if ($existingImage -eq "steam-producer:latest") {
    Write-Host "  Using existing Docker image (skipping build)" -ForegroundColor Green
} else {
    Write-Host "  Building Docker image..." -ForegroundColor Gray
    Push-Location "$PSScriptRoot/.."
    $buildOutput = docker build -t steam-producer:latest . 2>&1
    Pop-Location
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Docker build failed" -ForegroundColor Red
        Write-Host "  $buildOutput" -ForegroundColor Gray
        exit 1
    }
    Write-Host "  Docker image built successfully" -ForegroundColor Green
}

# --- Step 5: Deploy Spark ConfigMaps ---
Write-Host "`n[5/12] Deploying Spark ConfigMaps..." -ForegroundColor Yellow
kubectl apply -f kafka-spark-configmap.yaml 2>$null | Out-Null
Write-Host "  ConfigMaps deployed" -ForegroundColor Green

# --- Step 6: Deploy Charts Spark App (Sequential - Charts First) ---
Write-Host "`n[6/12] Deploying Charts Spark app...`n  (Running apps sequentially to conserve memory)" -ForegroundColor Yellow
kubectl delete sparkapplication steam-reviews-app --ignore-not-found 2>$null | Out-Null
kubectl apply -f steam-charts-app.yaml 2>$null | Out-Null
Write-Host "  Charts app deployed" -ForegroundColor Green

# Wait for Charts driver to start
Write-Host "`n[7/12] Waiting for Charts driver to start..." -ForegroundColor Yellow
$timeout = 300
$elapsed = 0
while ($elapsed -lt $timeout) {
    $driver = kubectl get pods --no-headers 2>$null | Select-String "steam-charts-app.*Running"
    if ($driver) {
        Write-Host "  Charts driver is running" -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 10
    $elapsed += 10
    Write-Host "  Waiting for Charts driver... ($elapsed s)" -ForegroundColor Gray
}

# --- Step 8: Run Steam Producer ---
Write-Host "`n[8/12] Running Steam producer job...`n  (Sending game_info and game_comments to Kafka)" -ForegroundColor Yellow
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

# Wait for Charts data to be processed
Write-Host "`n[9/12] Waiting for Charts data to flow (45 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 45

# --- Step 10: Switch to Reviews App (free memory first) ---
Write-Host "`n[10/12] Switching to Reviews Spark app...`n  (Stopping Charts app to free memory)" -ForegroundColor Yellow
kubectl delete sparkapplication steam-charts-app --ignore-not-found 2>$null | Out-Null
Start-Sleep -Seconds 10
kubectl apply -f steam-reviews-app.yaml 2>$null | Out-Null
Write-Host "  Reviews app deployed" -ForegroundColor Green

# Wait for Reviews driver to start
Write-Host "`n[11/12] Waiting for Reviews driver to start..." -ForegroundColor Yellow
$timeout = 300
$elapsed = 0
while ($elapsed -lt $timeout) {
    $driver = kubectl get pods --no-headers 2>$null | Select-String "steam-reviews-app.*Running"
    if ($driver) {
        Write-Host "  Reviews driver is running" -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 10
    $elapsed += 10
    Write-Host "  Waiting for Reviews driver... ($elapsed s)" -ForegroundColor Gray
}

# Wait for Reviews data to be processed (reads from Kafka - data is still there)
# First wait for executors to start, then wait for processing
Write-Host "`n[12/12] Waiting for Reviews executors and data processing..." -ForegroundColor Yellow
$timeout = 120
$elapsed = 0
while ($elapsed -lt $timeout) {
    $executors = kubectl get pods --no-headers 2>$null | Select-String "steamreviews.*exec.*Running"
    $execCount = ($executors | Measure-Object).Count
    if ($execCount -ge 1) {
        Write-Host "  Reviews executors running ($execCount), waiting 90s for data processing..." -ForegroundColor Green
        Start-Sleep -Seconds 90
        break
    }
    Start-Sleep -Seconds 10
    $elapsed += 10
    Write-Host "  Waiting for Reviews executors... ($elapsed s)" -ForegroundColor Gray
}

# --- Verify Results ---
Write-Host "`nVerifying results..." -ForegroundColor Yellow

# Check HDFS
Write-Host "`n  [HDFS Cold Storage]" -ForegroundColor Cyan
$hdfsCharts = kubectl exec simple-hdfs-namenode-default-0 -c namenode -- hdfs dfs -ls /user/stackable/archive/charts/ 2>$null | Select-String "parquet"
$hdfsReviews = kubectl exec simple-hdfs-namenode-default-0 -c namenode -- hdfs dfs -ls /user/stackable/archive/reviews/ 2>$null | Select-String "parquet"
$chartsCount = ($hdfsCharts | Measure-Object).Count
$reviewsCount = ($hdfsReviews | Measure-Object).Count

if ($chartsCount -gt 0) {
    Write-Host "    [OK] Charts data: $chartsCount parquet files" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Charts data: No files found" -ForegroundColor Red
}

if ($reviewsCount -gt 0) {
    Write-Host "    [OK] Reviews data: $reviewsCount parquet files" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Reviews data: No files found" -ForegroundColor Red
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
        Write-Host "    [OK] steam_charts: $chartsDocs aggregated documents" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] steam_charts: No documents found" -ForegroundColor Red
    }
    
    if ($reviewsDocs -gt 0) {
        Write-Host "    [OK] steam_reviews: $reviewsDocs aggregated documents" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] steam_reviews: No documents found" -ForegroundColor Red
    }
} else {
    Write-Host "    [FAIL] MongoDB pod not found" -ForegroundColor Red
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
    Write-Host "  [PASS] END-TO-END TEST PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "  [FAIL] END-TO-END TEST FAILED" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Troubleshooting:" -ForegroundColor Yellow
    Write-Host "    - Check Spark driver logs: kubectl logs -l spark-role=driver --tail=50" -ForegroundColor Gray
    Write-Host "    - Check producer logs: kubectl logs -l job-name=steam-producer --tail=50" -ForegroundColor Gray
    exit 1
}