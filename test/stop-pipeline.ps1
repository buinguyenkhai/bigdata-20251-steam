# stop-pipeline.ps1
# Gracefully stop the Steam Analytics WORKLOADS (not infrastructure)
# Infrastructure (ZooKeeper, Kafka, HDFS) stays running to avoid restart costs

$ErrorActionPreference = "Stop"
$rootDir = "$PSScriptRoot\.."

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Steam Analytics Pipeline - STOP         " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/4] Stopping Spark applications..." -ForegroundColor Yellow
kubectl delete sparkapplication steam-reviews-app steam-charts-app steam-players-app --ignore-not-found 2>$null | Out-Null
Write-Host "  Spark apps stopped" -ForegroundColor Green

Write-Host "[2/4] Stopping producer CronJobs..." -ForegroundColor Yellow
kubectl delete cronjob steam-producer-reviews steam-producer-charts --ignore-not-found 2>$null | Out-Null
Write-Host "  CronJobs stopped" -ForegroundColor Green

Write-Host "[3/4] Cleaning up any running jobs..." -ForegroundColor Yellow
kubectl delete jobs -l app=steam-producer-reviews --ignore-not-found 2>$null | Out-Null
kubectl delete jobs -l app=steam-producer-charts --ignore-not-found 2>$null | Out-Null
Write-Host "  Jobs cleaned up" -ForegroundColor Green

Write-Host "[4/4] Scaling down MongoDB..." -ForegroundColor Yellow
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
