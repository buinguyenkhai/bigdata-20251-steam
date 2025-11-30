$ErrorActionPreference = "Stop"

Write-Host "=== Spark Kafka Streaming Test ===" -ForegroundColor Cyan

Write-Host "`n[1/6] Checking prerequisites..." -ForegroundColor Yellow
$kafkaStatus = kubectl get pods -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].status.phase}' 2>$null
$hdfsStatus = kubectl get pods -l app.kubernetes.io/name=hdfs,app.kubernetes.io/component=namenode -o jsonpath='{.items[0].status.phase}' 2>$null

if ($kafkaStatus -ne "Running") {
    Write-Host "ERROR: Kafka not running. Run .\test\start.ps1 first." -ForegroundColor Red
    exit 1
}
if ($hdfsStatus -ne "Running") {
    Write-Host "ERROR: HDFS not running. Run .\test\start.ps1 first." -ForegroundColor Red
    exit 1
}
Write-Host "  Kafka: Running" -ForegroundColor Green
Write-Host "  HDFS: Running" -ForegroundColor Green

Write-Host "`n[2/6] Creating Kafka test topic..." -ForegroundColor Yellow
$topics = kubectl exec simple-kafka-broker-default-0 -c kafka -- bin/kafka-topics.sh --list --bootstrap-server localhost:9092 2>$null
if ($topics -notmatch "test-topic") {
    kubectl exec simple-kafka-broker-default-0 -c kafka -- bin/kafka-topics.sh --create --topic test-topic --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1 2>$null | Out-Null
    Write-Host "  Created topic: test-topic" -ForegroundColor Green
} else {
    Write-Host "  Topic test-topic already exists" -ForegroundColor Gray
}

Write-Host "`n[2/6] Deploying Spark Kafka app..." -ForegroundColor Yellow
kubectl apply -f kafka-test-configmap.yaml
kubectl delete sparkapplication kafka-test-output --ignore-not-found 2>$null
Start-Sleep -Seconds 2
kubectl apply -f kafka-test-app.yaml

Write-Host "`n[3/6] Waiting for Spark app to start (this may take 1-2 minutes)..." -ForegroundColor Yellow
$maxWait = 120
$waited = 0
$isRunning = $false

while ($waited -lt $maxWait) {
    $phase = kubectl get sparkapplication kafka-test-output -o jsonpath='{.status.phase}' 2>$null
    $driverPod = kubectl get pods -l spark-role=driver --no-headers 2>$null | Select-String "kafka-test-output"
    
    if ($phase -eq "Running" -or ($driverPod -and $driverPod -match "Running")) {
        $isRunning = $true
        Write-Host "Spark app is running!" -ForegroundColor Green
        break
    } elseif ($phase -eq "Failed") {
        Write-Host "Spark app failed to start. Check logs with:" -ForegroundColor Red
        Write-Host "  kubectl logs -l spark-role=driver --tail=50"
        exit 1
    }
    
    Write-Host "  Status: $phase - waiting..." -ForegroundColor Gray
    Start-Sleep -Seconds 10
    $waited += 10
}

if (-not $isRunning) {
    Write-Host "Timeout waiting for Spark app to start." -ForegroundColor Red
    exit 1
}

# Give Spark a moment to fully initialize streaming
Start-Sleep -Seconds 10

Write-Host "`n[4/6] Sending test messages to Kafka..." -ForegroundColor Yellow
$testMessages = @(
    "hello spark streaming",
    "test message from powershell",
    "bigdata project test"
)

foreach ($msg in $testMessages) {
    Write-Host "  Sending: '$msg'"
    echo $msg | kubectl exec -i simple-kafka-broker-default-0 -c kafka -- bin/kafka-console-producer.sh --topic test-topic --bootstrap-server localhost:9092 2>$null
    Start-Sleep -Seconds 2
}

# Wait for Spark to process
Write-Host "`n[5/6] Waiting 15 seconds for Spark to process messages..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

Write-Host "`n[6/6] Checking HDFS output..." -ForegroundColor Yellow

# Try to find the active namenode (HA-aware)
$activeNamenode = "simple-hdfs-namenode-default-0"
$nn0Status = kubectl exec simple-hdfs-namenode-default-0 -- hdfs haadmin -getServiceState nn0 2>$null
if ($nn0Status -match "standby") {
    $activeNamenode = "simple-hdfs-namenode-default-1"
}
$namenodeUrl = "http://${activeNamenode}.simple-hdfs-namenode-default.default.svc.cluster.local:9870"

$hdfsOutput = kubectl exec webhdfs-0 -- curl -s "${namenodeUrl}/webhdfs/v1/user/stackable/test-output?op=LISTSTATUS&user.name=stackable" 2>$null

if ($hdfsOutput -match "pathSuffix.*\.txt") {
    Write-Host "Output files found in HDFS!" -ForegroundColor Green
    
    # Extract and read the latest output files
    $files = ($hdfsOutput | ConvertFrom-Json).FileStatuses.FileStatus | Where-Object { $_.pathSuffix -match "\.txt$" -and $_.length -gt 0 }
    
    Write-Host "`n--- Output Content (should be UPPERCASE) ---" -ForegroundColor Cyan
    foreach ($file in $files | Select-Object -Last 5) {
        $content = kubectl exec webhdfs-0 -- curl -sL "${namenodeUrl}/webhdfs/v1/user/stackable/test-output/$($file.pathSuffix)?op=OPEN&user.name=stackable" 2>$null
        if ($content) {
            Write-Host "  $content"
        }
    }
    Write-Host "-------------------------------------------" -ForegroundColor Cyan
    
    # Verify uppercase conversion
    $allContent = $files | ForEach-Object {
        kubectl exec webhdfs-0 -- curl -sL "${namenodeUrl}/webhdfs/v1/user/stackable/test-output/$($_.pathSuffix)?op=OPEN&user.name=stackable" 2>$null
    }
    
    $hasUppercase = $allContent | Where-Object { $_ -cmatch "^[A-Z\s]+$" }
    if ($hasUppercase) {
        Write-Host "`n[PASSED] Spark Kafka app test succeeded!" -ForegroundColor Green
        Write-Host "Messages were correctly converted to UPPERCASE and saved to HDFS."
    } else {
        Write-Host "`n[WARNING] Output found but uppercase conversion not verified." -ForegroundColor Yellow
    }
} else {
    Write-Host "No output files found in HDFS." -ForegroundColor Red
    Write-Host "The Spark app may still be processing. Try running this test again."
    exit 1
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
