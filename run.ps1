# run.ps1
# Automates the entire workflow: Checks Infra -> setups Kafka -> Builds -> Runs Producers -> Verifies
$ErrorActionPreference = "Stop"

function Log-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Log-Success { param($msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Log-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Log-Error { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Host "============================================" -ForegroundColor Magenta
Write-Host "      Steam Data Pipeline Launcher         " -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

# --- 1. Check Infrastructure ---
Log-Info "Checking infrastructure consistency..."
$requiredPods = @("simple-kafka-broker", "simple-hdfs-namenode", "simple-zk-server")
foreach ($pod in $requiredPods) {
    try {
        $status = kubectl get pods 2>$null | Select-String $pod | Select-String "Running"
    } catch {
        Log-Error "kubectl failed. Ensure Kubernetes is running."
        exit 1
    }
    
    if (-not $status) {
        Log-Error "$pod pod is not running. Please check your Stackable operator deployment or run 'test/reset-all.ps1'."
        exit 1
    }
}
Log-Success "Infrastructure pods are running."

# --- 2. Setup Kafka Topics (SSL) ---
Log-Info "Setting up Kafka topics..."
$kafkaBrokerPod = "simple-kafka-broker-default-0"
$configCmd = "echo 'security.protocol=SSL' > /tmp/client.properties; echo 'ssl.truststore.location=/stackable/tls-kafka-server/truststore.p12' >> /tmp/client.properties; echo 'ssl.truststore.type=PKCS12' >> /tmp/client.properties; echo 'ssl.truststore.password=' >> /tmp/client.properties; echo 'ssl.keystore.location=/stackable/tls-kafka-server/keystore.p12' >> /tmp/client.properties; echo 'ssl.keystore.type=PKCS12' >> /tmp/client.properties; echo 'ssl.keystore.password=' >> /tmp/client.properties; echo 'ssl.endpoint.identification.algorithm=' >> /tmp/client.properties"

# Create config inside pod
Log-Info "Configuring SSL in Kafka broker..."
kubectl exec $kafkaBrokerPod -c kafka -- sh -c $configCmd
if ($LASTEXITCODE -ne 0) { Log-Error "Failed to configure SSL in Kafka pod."; exit 1 }

$kafkaCmdBase = "kafka-topics.sh --bootstrap-server localhost:9093 --command-config /tmp/client.properties"

# Wait for Kafka Readiness
Log-Info "Waiting for Kafka to reject connections or be ready..."
$kafkaReady = $false
for ($i=0; $i -lt 10; $i++) {
    kubectl exec $kafkaBrokerPod -c kafka -- sh -c "$kafkaCmdBase --list" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $kafkaReady = $true; break }
    Start-Sleep -Seconds 3
    Write-Host "." -NoNewline
}
Write-Host ""

if (-not $kafkaReady) { 
    Log-Error "Kafka is not reachable on localhost:9093."
    exit 1 
}

# Create Topics
Log-Info "Ensuring topics exist..."
$topics = @("game_info", "game_player_count", "game_comments")
$createCmd = ""
foreach ($t in $topics) {
    $createCmd += "$kafkaCmdBase --create --topic $t --partitions 3 --replication-factor 1 --if-not-exists; "
}
kubectl exec $kafkaBrokerPod -c kafka -- sh -c $createCmd 2>$null | Out-Null
Log-Success "Topics checked/created: $($topics -join ', ')"

# --- 3. Build Docker Image ---
Log-Info "Checking Docker image..."
$existingImage = docker images steam-producer:latest --format "{{.Repository}}:{{.Tag}}" 2>$null
if ($existingImage -eq "steam-producer:latest") {
    Log-Success "Using existing 'steam-producer:latest'."
} else {
    Log-Info "Building 'steam-producer:latest'..."
    docker build -t steam-producer:latest .
    if ($LASTEXITCODE -ne 0) { Log-Error "Docker build failed."; exit 1 }
    Log-Success "Docker build complete."
}

# --- 4. Deploy Jobs ---
Log-Info "Cleaning up old jobs..."
kubectl delete job steam-producer-reviews --ignore-not-found 2>$null | Out-Null
kubectl delete cronjob steam-producer-players --ignore-not-found 2>$null | Out-Null
# Also clean up manual manual player job if it exists
kubectl delete job steam-producer-players-manual --ignore-not-found 2>$null | Out-Null

Log-Info "Deploying Jobs..."
kubectl apply -f job-reviews.yaml
kubectl apply -f cronjob-players.yaml

# Trigger CronJob immediately for testing
Log-Info "Manually triggering player producer job..."
kubectl create job --from=cronjob/steam-producer-players steam-producer-players-manual

# --- 5. Monitor Execution ---
Log-Info "Waiting for 'steam-producer-reviews' to complete..."
$timeout = 180 # 3 minutes
$elapsed = 0
while ($elapsed -lt $timeout) {
    $status = kubectl get job steam-producer-reviews -o jsonpath='{.status.succeeded}' 2>$null
    if ($status -eq "1") {
        Log-Success "Reviews Producer Job Completed!"
        break
    }
    $failed = kubectl get job steam-producer-reviews -o jsonpath='{.status.failed}' 2>$null
    if ($failed -gt 0) {
        Log-Error "Reviews Producer Job Failed. Checking logs..."
        kubectl logs -l job-name=steam-producer-reviews --tail=50
        exit 1
    }
    
    Start-Sleep -Seconds 5
    $elapsed += 5
    if ($elapsed % 15 -eq 0) { Write-Host "Running... ($elapsed s)" -ForegroundColor Gray }
}

Log-Info "Checking manual player job..."
# We don't wait strictly for this one as it might be faster or slower, but we check if it's running
$pStatus = kubectl get job steam-producer-players-manual -o jsonpath='{.status.active}' 2>$null
if ($pStatus -eq "1") { Log-Info "Player producer is still running (this is normal)." }
else { Log-Success "Player producer finished." }

# --- 6. Quick Verification ---
Log-Info "Verifying Kafka Messages..."
Start-Sleep -Seconds 5 # Give a moment for last commits

$offsetCmdBase = "kafka-run-class.sh org.apache.kafka.tools.GetOffsetShell --broker-list localhost:9093 --command-config /tmp/client.properties --time -1"
foreach ($topic in $topics) {
    $output = kubectl exec $kafkaBrokerPod -c kafka -- sh -c "$offsetCmdBase --topic $topic" 2>$null
    $count = 0
    if ($output) {
        $output -split "`n" | ForEach-Object {
             if ($_ -match ":\d+:(\d+)") { $count += [int]$matches[1] }
        }
    }
    if ($count -gt 0) { Log-Success "Topic '$topic' has $count messages." }
    else { Log-Warn "Topic '$topic' is EMPTY." }
}

Log-Info "Run 'test/verify-kafka-state.ps1' for detailed inspections."
Exit 0
