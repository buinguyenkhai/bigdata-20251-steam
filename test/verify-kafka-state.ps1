# verify-kafka-state.ps1
# Verifies Kafka topics, broker status, message counts, and Spark consumption

$ErrorActionPreference = "Continue"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       Kafka State Verification            " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# 1. Broker Status
Write-Host "`n[1/4] Checking Broker Status..." -ForegroundColor Yellow
$brokerPods = kubectl get pods -l app.kubernetes.io/name=kafka --no-headers 2>$null | Select-String "Running"
$brokerCount = ($brokerPods | Measure-Object).Count
if ($brokerCount -gt 0) {
    Write-Host "  Brokers Running: $brokerCount" -ForegroundColor Green
} else {
    Write-Host "  WARNING: No running Kafka broker pods found." -ForegroundColor Red
}

# 2. Topic List and Count
Write-Host "`n[2/4] Checking Topics..." -ForegroundColor Yellow
$configCmd = "/tmp/client.properties" # Assumes this was created by test-e2e-pipeline.ps1/test-kafka.ps1
# Verify config exists
$checkConfig = kubectl exec simple-kafka-broker-default-0 -c kafka -- sh -c "ls $configCmd" 2>$null
if ($LASTEXITCODE -ne 0) {
     Write-Host "  Re-creating client.properties..." -ForegroundColor Gray
     $setupCmd = "echo 'security.protocol=SSL' > /tmp/client.properties; echo 'ssl.truststore.location=/stackable/tls-kafka-server/truststore.p12' >> /tmp/client.properties; echo 'ssl.truststore.type=PKCS12' >> /tmp/client.properties; echo 'ssl.truststore.password=' >> /tmp/client.properties; echo 'ssl.keystore.location=/stackable/tls-kafka-server/keystore.p12' >> /tmp/client.properties; echo 'ssl.keystore.type=PKCS12' >> /tmp/client.properties; echo 'ssl.keystore.password=' >> /tmp/client.properties; echo 'ssl.endpoint.identification.algorithm=' >> /tmp/client.properties"
     kubectl exec simple-kafka-broker-default-0 -c kafka -- sh -c $setupCmd
}

$kafkaCmdBase = "kafka-topics.sh --bootstrap-server localhost:9093 --command-config /tmp/client.properties"
# Redirect stderr to null to avoid log noise, filter stdout for clean topic names
$topicsRaw = kubectl exec simple-kafka-broker-default-0 -c kafka -- sh -c "$kafkaCmdBase --list" 2>$null
# Filter out empty lines, log lines, and config lines. Use strict AllowList for topic names.
$topics = $topicsRaw -split "`r`n" | Where-Object { 
    $t = $_.Trim()
    $t -and ($t -match "^[a-zA-Z0-9._-]+$")
}
$topicCount = ($topics | Measure-Object).Count
Write-Host "  Total Topics: $topicCount" -ForegroundColor Cyan
$topics | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }

if ($topicCount -eq 0) {
    Write-Host "  ERROR: No topics found!" -ForegroundColor Red
    exit 1
}

# 3. Message Counts per Topic
Write-Host "`n[3/4] Checking Message Counts (Offsets)..." -ForegroundColor Yellow
$offsetCmdBase = "kafka-run-class.sh org.apache.kafka.tools.GetOffsetShell --broker-list localhost:9093 --command-config /tmp/client.properties --time -1"
foreach ($topic in $topics) {
    # Get offsets (format: topic:partition:offset). Suppress stderr in exec.
    $output = kubectl exec simple-kafka-broker-default-0 -c kafka -- sh -c "$offsetCmdBase --topic $topic" 2>$null
    
    $totalMessages = 0
    if ($output) {
        $lines = $output -split "`n"
        foreach ($line in $lines) {
            # Trim whitespace and check format
            $line = $line.Trim()
            if ($line -match "^${topic}:\d+:(\d+)$") {
                $totalMessages += [long]$matches[1]
            }
        }
    }
    
    if ($totalMessages -gt 0) {
        Write-Host "  $topic : $totalMessages messages" -ForegroundColor Green
    } else {
        Write-Host "  $topic : 0 messages (or failed to get offsets)" -ForegroundColor Yellow
    }
}

# 4. Consumption Test (Console Consumer)
Write-Host "`n[4/4] Verifying Consumption (Console Consumer)..." -ForegroundColor Yellow

$consumerCmdBase = "kafka-console-consumer.sh --bootstrap-server localhost:9093 --consumer.config /tmp/client.properties --from-beginning --max-messages 1 --timeout-ms 20000 --partition 0"


foreach ($topic in $topics) {
    Write-Host "  Reading from $topic..." -ForegroundColor Gray
    
    # Run consumer, modify logic to isolate the message.
    # We redirect stderr to $null to avoid capturing logs in $msg.
    # NOTE: In PowerShell, simply running the command captures stdout. Stderr goes to stream 2.
    # To suppress logs effectively from the variable, we redirect 2>/dev/null INSIDE the sh command if possible,
    # or use 2>$null in PowerShell.
    
    # To suppress logs effectively from the variable, we redirect 2>/dev/null INSIDE the sh command.
    # We also use --partition 0 to bypass group coordination logs.
    $msg = kubectl exec simple-kafka-broker-default-0 -c kafka -- sh -c "$consumerCmdBase --topic $topic 2>/dev/null" 2>$null
    $exitCode = $LASTEXITCODE

    if ($msg) {
         # We have output, which should be the message since we suppressed logs
         Write-Host "    [SUCCESS] Connected and consumed message." -ForegroundColor Green
         # Try to extract the message content (lines not matching "Processed a total" and not log lines)
             $content = $msg -split "`n" | Where-Object { 
                 $line = $_.Trim()
                 $line.Length -gt 0 -and 
                 $line -notmatch "Processed a total" -and 
                 $line -notmatch "^\[" -and 
                 $line -notmatch "INFO" -and 
                 $line -notmatch "WARN"
             }
             if ($content) {
                 $display = $content -join "`n"
                 # if ($display.Length -gt 200) { $display = $display.Substring(0, 200) + "..." } # Removed truncation per user request
                 Write-Host "    Message Content:" -ForegroundColor White
                 Write-Host "    $display" -ForegroundColor Gray
             } else {
                 Write-Host "    [WARNING] No message content found after filtering logs." -ForegroundColor Yellow
             }
    } else {
         # If no output, check if it was a timeout or error (we suppressed error output, so this is a bit blind)
         # We can try running again with stderr if it failed? No, let's just assume empty/timeout.
         Write-Host "    [WARNING] No message received (or timed out/error)." -ForegroundColor Yellow
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
