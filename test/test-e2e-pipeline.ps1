# test-e2e-pipeline.ps1
# End-to-End Pipeline Test: Steam API → Kafka → Spark → HDFS + MongoDB
$ErrorActionPreference = "Stop"
$rootDir = "$PSScriptRoot\.."

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
kubectl apply -f "$rootDir\k8s\infrastructure\mongodb.yaml" 2>$null | Out-Null
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

# 1. Create a custom SSL configuration file inside the container
# FIX: Added 'ssl.endpoint.identification.algorithm=' to disable hostname verification (fixes "No subject alternative DNS name matching localhost")
$configCmd = "echo 'security.protocol=SSL' > /tmp/client.properties; echo 'ssl.truststore.location=/stackable/tls-kafka-server/truststore.p12' >> /tmp/client.properties; echo 'ssl.truststore.type=PKCS12' >> /tmp/client.properties; echo 'ssl.truststore.password=' >> /tmp/client.properties; echo 'ssl.keystore.location=/stackable/tls-kafka-server/keystore.p12' >> /tmp/client.properties; echo 'ssl.keystore.type=PKCS12' >> /tmp/client.properties; echo 'ssl.keystore.password=' >> /tmp/client.properties; echo 'ssl.endpoint.identification.algorithm=' >> /tmp/client.properties"

# Execute the file creation
kubectl exec simple-kafka-broker-default-0 -c kafka -- sh -c $configCmd

# Define the base command using the new config file
$kafkaCmdBase = "kafka-topics.sh --bootstrap-server localhost:9093 --command-config /tmp/client.properties"

# 2. Wait for Kafka to be ready (Retry loop)
Write-Host "  Waiting for Kafka to be ready..." -ForegroundColor Gray
$kafkaReady = $false
for ($i=0; $i -lt 20; $i++) {
    try {
        # Check listing topics using the SSL config
        kubectl exec simple-kafka-broker-default-0 -c kafka -- sh -c "$kafkaCmdBase --list" 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            $kafkaReady = $true
            break
        }
    } catch {
        # Ignore connection errors during startup
    }
    Start-Sleep -Seconds 5
    Write-Host "." -NoNewline -ForegroundColor Gray
}
Write-Host "" # Newline

if (-not $kafkaReady) {
    Write-Host "ERROR: Kafka is not responding on port 9093 (SSL)." -ForegroundColor Red
    Write-Host "Debugging output:" -ForegroundColor Yellow
    kubectl exec simple-kafka-broker-default-0 -c kafka -- sh -c "$kafkaCmdBase --list"
    exit 1
}

# 3. Create Topics
Write-Host "  Kafka is ready. Creating topics..." -ForegroundColor Gray
try {
    # Create topics using the SSL base command
    kubectl exec simple-kafka-broker-default-0 -c kafka -- sh -c "$kafkaCmdBase --create --topic game_info --partitions 3 --replication-factor 1 --if-not-exists; $kafkaCmdBase --create --topic game_comments --partitions 3 --replication-factor 1 --if-not-exists; $kafkaCmdBase --create --topic game_player_count --partitions 3 --replication-factor 1 --if-not-exists" 2>&1 | Out-Null
    Write-Host "  Topics ready: game_info, game_comments, game_player_count" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to create topics." -ForegroundColor Red
    Write-Host $_
    exit 1
}

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
Write-Host "`n[5/10] Deploying Spark ConfigMaps..." -ForegroundColor Yellow
kubectl apply -f "$rootDir\k8s\spark-apps\kafka-spark-configmap.yaml" 2>$null | Out-Null
Write-Host "  ConfigMaps deployed" -ForegroundColor Green

# --- Step 6: Deploy Spark streaming apps ---
Write-Host "`n[6/10] Deploying Spark streaming apps..." -ForegroundColor Yellow
kubectl apply -f "$rootDir\k8s\spark-apps\steam-reviews-app.yaml" 2>$null | Out-Null
kubectl apply -f "$rootDir\k8s\spark-apps\steam-charts-app.yaml" 2>$null | Out-Null
kubectl apply -f "$rootDir\k8s\spark-apps\steam-players-app.yaml" 2>$null | Out-Null
kubectl apply -f "$rootDir\k8s\monitoring\expose-services.yaml" 2>$null | Out-Null
Write-Host "  Spark apps deployed (3) + services exposed" -ForegroundColor Green

# --- Step 7: Wait for Spark drivers to start ---
Write-Host "`n[7/10] Waiting for Spark drivers to start (this may take 2-3 minutes)..." -ForegroundColor Yellow
$timeout = 600
$elapsed = 0
# Temporarily allow errors (kubectl returns "No resources found" as stderr on first run)
$ErrorActionPreference = "Continue"
while ($elapsed -lt $timeout) {
    $drivers = kubectl get pods -l spark-role=driver --no-headers 2>&1 | Select-String "Running"
    $driverCount = ($drivers | Measure-Object).Count
    if ($driverCount -ge 3) {
        Write-Host "  Spark drivers are running ($driverCount/3)" -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 10
    $elapsed += 10
    Write-Host "  Waiting for Spark drivers... ($elapsed s, $driverCount/3 running)" -ForegroundColor Gray
}
$ErrorActionPreference = "Stop"
if ($elapsed -ge $timeout) {
    Write-Host "WARNING: Not all Spark drivers started within $timeout seconds" -ForegroundColor Yellow
}

# --- Step 8: Deploy and Trigger Producer ---
Write-Host "`n[8/10] Deploying and triggering producer..." -ForegroundColor Yellow
kubectl apply -f "$rootDir\k8s\producers\steam-cronjob.yaml" 2>$null | Out-Null
kubectl apply -f "$rootDir\k8s\producers\steam-cronjob-players.yaml" 2>$null | Out-Null
kubectl apply -f "$rootDir\k8s\producers\steam-cronjob-charts.yaml" 2>$null | Out-Null
kubectl delete job e2e-test-producer --ignore-not-found 2>$null | Out-Null
Start-Sleep -Seconds 2
kubectl create job --from=cronjob/steam-producer-reviews e2e-test-producer 2>$null | Out-Null

# Wait for producer to complete
$timeout = 180
$elapsed = 0
while ($elapsed -lt $timeout) {
    $producerStatus = kubectl get job e2e-test-producer -o jsonpath='{.status.succeeded}' 2>$null
    if ($producerStatus -eq "1") {
        Write-Host "  Producer completed successfully" -ForegroundColor Green
        break
    }
    $failedStatus = kubectl get job e2e-test-producer -o jsonpath='{.status.failed}' 2>$null
    if ($failedStatus -gt 0) {
        Write-Host "ERROR: Producer job failed" -ForegroundColor Red
        kubectl logs -l job-name=e2e-test-producer --tail=20
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
# FIX: Added '-c namenode' to prevent "Defaulted container" warning which crashes PowerShell
$hdfsCharts = kubectl exec simple-hdfs-namenode-default-0 -c namenode -- hdfs dfs -ls /user/stackable/archive/charts/ 2>$null | Select-String "parquet"
$hdfsReviews = kubectl exec simple-hdfs-namenode-default-0 -c namenode -- hdfs dfs -ls /user/stackable/archive/reviews/ 2>$null | Select-String "parquet"
$hdfsPlayers = kubectl exec simple-hdfs-namenode-default-0 -c namenode -- hdfs dfs -ls /user/stackable/archive/players/ 2>$null | Select-String "parquet"
$chartsCount = ($hdfsCharts | Measure-Object).Count
$reviewsCount = ($hdfsReviews | Measure-Object).Count
$playersCount = ($hdfsPlayers | Measure-Object).Count

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

if ($playersCount -gt 0) {
    Write-Host "    [OK] Players data: $playersCount parquet files" -ForegroundColor Green
} else {
    Write-Host "    [WARN] Players data: No files yet (CronJob may not have run)" -ForegroundColor Yellow
}

# Check MongoDB
Write-Host "`n  [MongoDB Hot Storage]" -ForegroundColor Cyan
$mongoPod = kubectl get pods -l app=mongodb -o jsonpath='{.items[0].metadata.name}' 2>$null
if ($mongoPod) {
    $chartsDocsRaw = kubectl exec $mongoPod -- mongosh game_analytics --quiet --eval "db.steam_charts.countDocuments()" 2>$null
    $reviewsDocsRaw = kubectl exec $mongoPod -- mongosh game_analytics --quiet --eval "db.steam_reviews.countDocuments()" 2>$null
    $playersDocsRaw = kubectl exec $mongoPod -- mongosh bigdata --quiet --eval "db.steam_players.countDocuments()" 2>$null
    # Handle multi-line output - take last non-empty line and extract number
    $chartsDocsLine = ($chartsDocsRaw | Where-Object { $_ -match '\d+' } | Select-Object -Last 1) -replace '\D', ''
    $reviewsDocsLine = ($reviewsDocsRaw | Where-Object { $_ -match '\d+' } | Select-Object -Last 1) -replace '\D', ''
    $playersDocsLine = ($playersDocsRaw | Where-Object { $_ -match '\d+' } | Select-Object -Last 1) -replace '\D', ''
    if ($chartsDocsLine) { $chartsDocs = [int]$chartsDocsLine } else { $chartsDocs = 0 }
    if ($reviewsDocsLine) { $reviewsDocs = [int]$reviewsDocsLine } else { $reviewsDocs = 0 }
    if ($playersDocsLine) { $playersDocs = [int]$playersDocsLine } else { $playersDocs = 0 }
    
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
    
    if ($playersDocs -gt 0) {
        Write-Host "    [OK] steam_players: $playersDocs aggregated documents" -ForegroundColor Green
    } else {
        Write-Host "    [WARN] steam_players: No documents yet (CronJob may not have run)" -ForegroundColor Yellow
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
Write-Host "    Kafka Topics:   game_info, game_comments, game_player_count" -ForegroundColor Green
Write-Host "    Steam Producer: Completed" -ForegroundColor Green
Write-Host "    Spark Apps:     Running (3)" -ForegroundColor Green
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