# stop-pipeline.ps1
# Gracefully stop the Steam Analytics WORKLOADS (not infrastructure)
# Infrastructure (ZooKeeper, Kafka, HDFS) stays running to avoid restart costs

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Steam Analytics Pipeline - STOP         " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/3] Stopping Spark applications..." -ForegroundColor Yellow
kubectl delete sparkapplication steam-reviews-app steam-charts-app --ignore-not-found 2>$null | Out-Null
Write-Host "  Spark apps stopped" -ForegroundColor Green

Write-Host "[2/3] Stopping producer job..." -ForegroundColor Yellow
kubectl delete job steam-producer --ignore-not-found 2>$null | Out-Null
Write-Host "  Producer job stopped" -ForegroundColor Green

Write-Host "[3/3] Scaling down MongoDB..." -ForegroundColor Yellow
kubectl scale deployment mongodb --replicas=0 2>$null | Out-Null
Write-Host "  MongoDB scaled to 0" -ForegroundColor Green

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Workloads STOPPED Successfully          " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Infrastructure (ZooKeeper, Kafka, HDFS) is still running." -ForegroundColor Gray
Write-Host "This uses ~3-4GB RAM but avoids long restart times." -ForegroundColor Gray
Write-Host ""
Write-Host "To resume the pipeline, run:" -ForegroundColor White
Write-Host "  .\test\resume-pipeline.ps1" -ForegroundColor Yellow
Write-Host ""
Write-Host "To stop EVERYTHING (including infrastructure), close Docker Desktop" -ForegroundColor Gray
Write-Host "or run: .\test\reset-all.ps1 (will delete all data)" -ForegroundColor Gray
