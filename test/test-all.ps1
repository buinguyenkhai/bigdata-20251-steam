# test-all.ps1
# Run all tests in sequence: HDFS, Kafka, and Spark Kafka App
$ErrorActionPreference = "Stop"
$testDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       BigData Project - Full Test Suite    " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$results = @{}

# --- Test 1: HDFS ---
Write-Host ">>> Running HDFS Test..." -ForegroundColor Magenta
try {
    & "$testDir\test-hdfs.ps1"
    $results["HDFS"] = "PASSED"
    Write-Host "[HDFS] Test PASSED" -ForegroundColor Green
} catch {
    $results["HDFS"] = "FAILED"
    Write-Host "[HDFS] Test FAILED: $_" -ForegroundColor Red
}
Write-Host ""

# --- Test 2: Kafka ---
Write-Host ">>> Running Kafka Test..." -ForegroundColor Magenta
try {
    & "$testDir\test-kafka.ps1"
    $results["Kafka"] = "PASSED"
    Write-Host "[Kafka] Test PASSED" -ForegroundColor Green
} catch {
    $results["Kafka"] = "FAILED"
    Write-Host "[Kafka] Test FAILED: $_" -ForegroundColor Red
}
Write-Host ""

# --- Test 3: Spark Kafka App ---
Write-Host ">>> Running Spark Kafka App Test..." -ForegroundColor Magenta
try {
    & "$testDir\test-spark-kafka-app.ps1"
    $results["Spark-Kafka-App"] = "PASSED"
    Write-Host "[Spark-Kafka-App] Test PASSED" -ForegroundColor Green
} catch {
    $results["Spark-Kafka-App"] = "FAILED"
    Write-Host "[Spark-Kafka-App] Test FAILED: $_" -ForegroundColor Red
}
Write-Host ""

# --- Summary ---
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "              TEST SUMMARY                  " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$passed = 0
$failed = 0
foreach ($test in $results.Keys) {
    $status = $results[$test]
    if ($status -eq "PASSED") {
        Write-Host "  [PASS] $test" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  [FAIL] $test" -ForegroundColor Red
        $failed++
    }
}

Write-Host "--------------------------------------------"
Write-Host "  Total: $($passed + $failed) | Passed: $passed | Failed: $failed"
Write-Host "============================================" -ForegroundColor Cyan

if ($failed -gt 0) {
    exit 1
}
