$ErrorActionPreference = "Stop"

Write-Host "=== Kafka Produce/Consume Test ===" -ForegroundColor Cyan

Write-Host "`n[1/5] Checking Kafka broker..." -ForegroundColor Yellow
$kafkaPod = kubectl get pods -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].status.phase}' 2>$null
if ($kafkaPod -ne "Running") {
    Write-Host "ERROR: Kafka broker not running. Run .\test\start.ps1 first." -ForegroundColor Red
    exit 1
}
Write-Host "  Kafka broker is running" -ForegroundColor Green

Write-Host "`n[2/5] Creating test topic..." -ForegroundColor Yellow
$topics = kubectl exec simple-kafka-broker-default-0 -c kafka -- bin/kafka-topics.sh --list --bootstrap-server localhost:9092 2>$null
if ($topics -notmatch "test-data-topic") {
    kubectl exec simple-kafka-broker-default-0 -c kafka -- bin/kafka-topics.sh --create --bootstrap-server localhost:9092 --topic test-data-topic --partitions 1 --replication-factor 1 2>$null | Out-Null
    Write-Host "  Created topic: test-data-topic" -ForegroundColor Green
} else {
    Write-Host "  Topic test-data-topic already exists" -ForegroundColor Gray
}

Write-Host "`n[3/5] Producing test message..." -ForegroundColor Yellow
$testMessage = "kafka-test-message-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# Use kubectl exec to produce message via console producer
$produceCmd = "echo '$testMessage' | bin/kafka-console-producer.sh --broker-list localhost:9092 --topic test-data-topic"
kubectl exec simple-kafka-broker-default-0 -c kafka -- bash -c $produceCmd 2>$null
Write-Host "  Produced: $testMessage" -ForegroundColor Green

Write-Host "`n[4/5] Consuming message..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

$consumeCmd = "timeout 5 bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic test-data-topic --from-beginning --max-messages 10 2>/dev/null || true"
$consumed = kubectl exec simple-kafka-broker-default-0 -c kafka -- bash -c $consumeCmd 2>$null

if ($consumed -match $testMessage) {
    Write-Host "  Consumed and verified message!" -ForegroundColor Green
    $success = $true
} else {
    Write-Host "  Message verification failed" -ForegroundColor Red
    Write-Host "  Expected: $testMessage" -ForegroundColor Gray
    Write-Host "  Got: $consumed" -ForegroundColor Gray
    $success = $false
}

Write-Host "`n[5/5] Test Summary" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
if ($success) {
    Write-Host "  [PASS] KAFKA TEST PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "  [FAIL] KAFKA TEST FAILED" -ForegroundColor Red
    exit 1
}