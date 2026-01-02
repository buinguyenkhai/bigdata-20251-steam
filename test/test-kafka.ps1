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
    kubectl exec simple-kafka-broker-default-0 -c kafka -- sh -c "$kafkaCmdBase --create --topic game_info --partitions 3 --replication-factor 1 --if-not-exists; $kafkaCmdBase --create --topic game_player_count --partitions 3 --replication-factor 1 --if-not-exists; $kafkaCmdBase --create --topic game_comments --partitions 3 --replication-factor 1 --if-not-exists" 2>&1 | Out-Null
    Write-Host "  Topics ready: game_info, game_player_count, game_comments" -ForegroundColor Green
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


# --- Step 8: Run Steam Producer ---
Write-Host "`n[8/10] Running Steam producer job..." -ForegroundColor Yellow
kubectl delete job steam-producer --ignore-not-found 2>$null | Out-Null
Start-Sleep -Seconds 2
kubectl apply -f steam-job.yaml 2>$null | Out-Null

# Wait for producer to complete
$timeout = 120
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