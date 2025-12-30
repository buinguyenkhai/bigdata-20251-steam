$ErrorActionPreference = "Stop"

Write-Host "=== HDFS Read/Write Test ===" -ForegroundColor Cyan

Write-Host "`n[1/6] Checking HDFS components..." -ForegroundColor Yellow
$namenodeStatus = kubectl get pods -l app.kubernetes.io/name=hdfs,app.kubernetes.io/component=namenode -o jsonpath='{.items[0].status.phase}' 2>$null
$datanodeStatus = kubectl get pods -l app.kubernetes.io/name=hdfs,app.kubernetes.io/component=datanode -o jsonpath='{.items[0].status.phase}' 2>$null

if ($namenodeStatus -ne "Running") {
    Write-Host "ERROR: HDFS NameNode not running. Run .\test\start.ps1 first." -ForegroundColor Red
    exit 1
}
if ($datanodeStatus -ne "Running") {
    Write-Host "ERROR: HDFS DataNode not running. Run .\test\start.ps1 first." -ForegroundColor Red
    exit 1
}
Write-Host "  NameNode: Running" -ForegroundColor Green
Write-Host "  DataNode: Running" -ForegroundColor Green

Write-Host "`n[2/6] Ensuring WebHDFS helper is available..." -ForegroundColor Yellow
$webhdfsStatus = kubectl get pods -l app=webhdfs -o jsonpath='{.items[0].status.phase}' 2>$null
if ($webhdfsStatus -ne "Running") {
    kubectl apply -f webhdfs.yaml 2>$null | Out-Null
    Write-Host "  Deploying WebHDFS helper..." -ForegroundColor Gray
    $timeout = 60
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        $webhdfsStatus = kubectl get pods -l app=webhdfs -o jsonpath='{.items[0].status.phase}' 2>$null
        if ($webhdfsStatus -eq "Running") { break }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
}
Write-Host "  WebHDFS helper: Running" -ForegroundColor Green

Write-Host "`n[3/6] Finding active NameNode..." -ForegroundColor Yellow
$activeNN = "simple-hdfs-namenode-default-0"
$nn0State = kubectl exec simple-hdfs-namenode-default-0 -- hdfs haadmin -getServiceState nn0 2>$null
if ($nn0State -match "standby") {
    $activeNN = "simple-hdfs-namenode-default-1"
}
Write-Host "  Active NameNode: $activeNN" -ForegroundColor Green

Write-Host "`n[4/6] Uploading test file to HDFS..." -ForegroundColor Yellow
$testContent = "hdfs-test-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$testFile = "/user/stackable/test-hdfs-$((Get-Random)).txt"

# Write directly using hdfs dfs command
$uploadCmd = "echo '$testContent' | hdfs dfs -put - $testFile"
kubectl exec $activeNN -- bash -c $uploadCmd 2>$null
Write-Host "  Uploaded to: $testFile" -ForegroundColor Green

Write-Host "`n[5/6] Reading file from HDFS..." -ForegroundColor Yellow
$readContent = kubectl exec $activeNN -- hdfs dfs -cat $testFile 2>$null

if ($readContent -match $testContent) {
    Write-Host "  Content verified!" -ForegroundColor Green
    $success = $true
} else {
    Write-Host "  Content mismatch!" -ForegroundColor Red
    Write-Host "  Expected: $testContent" -ForegroundColor Gray
    Write-Host "  Got: $readContent" -ForegroundColor Gray
    $success = $false
}

Write-Host "`n[6/6] Cleaning up..." -ForegroundColor Yellow
kubectl exec $activeNN -- hdfs dfs -rm $testFile 2>$null | Out-Null
Write-Host "  Removed test file" -ForegroundColor Gray

Write-Host "`n============================================" -ForegroundColor Cyan
if ($success) {
    Write-Host "  [PASS] HDFS TEST PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "  [FAIL] HDFS TEST FAILED" -ForegroundColor Red
    exit 1
}