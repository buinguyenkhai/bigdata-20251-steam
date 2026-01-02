# test-new-producers.ps1
# Tests the Refactored Producers (Reviews Job + Players CronJob)
$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Testing New Steam Producers             " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 0: Cleanup Previous Run ---
Write-Host "[0/5] Cleaning up previous jobs..." -ForegroundColor Yellow
kubectl delete job steam-producer-reviews --ignore-not-found 2>$null | Out-Null
kubectl delete cronjob steam-producer-players --ignore-not-found 2>$null | Out-Null
kubectl delete job manual-players-trigger --ignore-not-found 2>$null | Out-Null
kubectl delete job steam-producer --ignore-not-found 2>$null | Out-Null # Old job
Write-Host "  Deleted old jobs." -ForegroundColor Gray

# --- Step 1: Ensure Kafka Topics Exists ---
# This reuses the existing logic to ensure topics are there, but assumes Kafka is up.
Write-Host "`n[1/5] Ensuring Kafka Topics..." -ForegroundColor Yellow
# Using the verify script's knowledge or just running creation again (idempotent with --if-not-exists)
# We need the config file to exist first usually.
$configCmd = "echo 'security.protocol=SSL' > /tmp/client.properties; echo 'ssl.truststore.location=/stackable/tls-kafka-server/truststore.p12' >> /tmp/client.properties; echo 'ssl.truststore.type=PKCS12' >> /tmp/client.properties; echo 'ssl.truststore.password=' >> /tmp/client.properties; echo 'ssl.keystore.location=/stackable/tls-kafka-server/keystore.p12' >> /tmp/client.properties; echo 'ssl.keystore.type=PKCS12' >> /tmp/client.properties; echo 'ssl.keystore.password=' >> /tmp/client.properties; echo 'ssl.endpoint.identification.algorithm=' >> /tmp/client.properties"
kubectl exec simple-kafka-broker-default-0 -c kafka -- sh -c $configCmd
$kafkaCmdBase = "kafka-topics.sh --bootstrap-server localhost:9093 --command-config /tmp/client.properties"

try {
    kubectl exec simple-kafka-broker-default-0 -c kafka -- sh -c "$kafkaCmdBase --create --topic game_info --partitions 3 --replication-factor 1 --if-not-exists; $kafkaCmdBase --create --topic game_player_count --partitions 3 --replication-factor 1 --if-not-exists; $kafkaCmdBase --create --topic game_comments --partitions 3 --replication-factor 1 --if-not-exists" 2>&1 | Out-Null
    Write-Host "  Topics ready." -ForegroundColor Green
} catch {
    Write-Host "WARNING: Could not create topics (Kafka might be down or busy)." -ForegroundColor Yellow
}

# --- Step 2: Build Docker Image ---
Write-Host "`n[2/5] Building Steam Producer Image..." -ForegroundColor Yellow
Push-Location "$PSScriptRoot/.."
# Temporarily relax error action because docker sends progress to stderr
$ErrorActionPreference = "Continue"
$buildOutput = docker build -t steam-producer:latest . 2>&1
$buildExitCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"
Pop-Location

if ($buildExitCode -ne 0) {
    Write-Host "ERROR: Docker build failed" -ForegroundColor Red
    Write-Host "  $buildOutput" -ForegroundColor Gray
    exit 1
}
Write-Host "  Docker image built successfully" -ForegroundColor Green

# --- Step 3: Deploy Reviews Producer (Job) ---
Write-Host "`n[3/5] Deploying Reviews Producer (Job)..." -ForegroundColor Yellow
kubectl apply -f job-reviews.yaml 2>$null | Out-Null
Write-Host "  Job 'steam-producer-reviews' created." -ForegroundColor Gray

# --- Step 4: Deploy Players Producer (CronJob) ---
Write-Host "`n[4/5] Deploying Players Producer (CronJob)..." -ForegroundColor Yellow
kubectl apply -f cronjob-players.yaml 2>$null | Out-Null
Write-Host "  CronJob 'steam-producer-players' created." -ForegroundColor Gray

# Trigger manually for testing
Write-Host "  Triggering manual run of Players Producer..." -ForegroundColor Gray
kubectl create job --from=cronjob/steam-producer-players manual-players-trigger 2>$null | Out-Null

# --- Step 5: Wait and Monitor ---
Write-Host "`n[5/5] Monitoring Jobs..." -ForegroundColor Yellow
$timeout = 180
$elapsed = 0

while ($elapsed -lt $timeout) {
    $reviewsStatus = kubectl get pods -l job-name=steam-producer-reviews -o jsonpath='{.items[0].status.phase}' 2>$null
    $playersStatus = kubectl get pods -l job-name=manual-players-trigger -o jsonpath='{.items[0].status.phase}' 2>$null
    
    # Check if both are done (Succeeded or Failed)
    $reviewsDone = ($reviewsStatus -eq "Succeeded" -or $reviewsStatus -eq "Failed")
    $playersDone = ($playersStatus -eq "Succeeded" -or $playersStatus -eq "Failed")
    
    Write-Host "`r  Reviews: $reviewsStatus | Players: $playersStatus ($elapsed s)   " -NoNewline -ForegroundColor Gray
    
    if ($reviewsDone -and $playersDone) {
        Write-Host ""
        if ($reviewsStatus -eq "Succeeded") { Write-Host "  [PASS] Reviews Job Succeeded" -ForegroundColor Green }
        else { Write-Host "  [FAIL] Reviews Job Failed" -ForegroundColor Red; kubectl logs -l job-name=steam-producer-reviews --tail=20 }
        
        if ($playersStatus -eq "Succeeded") { Write-Host "  [PASS] Players Job Succeeded" -ForegroundColor Green }
        else { Write-Host "  [FAIL] Players Job Failed" -ForegroundColor Red; kubectl logs -l job-name=manual-players-trigger --tail=20 }
        break
    }
    
    Start-Sleep -Seconds 5
    $elapsed += 5
}

Write-Host "`nDone. Run '.\test\verify-kafka-state.ps1' to verify data." -ForegroundColor Cyan
