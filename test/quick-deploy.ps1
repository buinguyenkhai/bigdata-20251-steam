# quick-deploy.ps1
# Quick deployment script for faster iteration during development
# Skips infrastructure reset - only redeploys application components

param(
    [switch]$SkipBuild,
    [switch]$Full
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Quick Deploy - Steam Analytics Pipeline  " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

if ($Full) {
    Write-Host "`nRunning FULL deployment (includes infrastructure)..." -ForegroundColor Yellow
    & "$PSScriptRoot\reset-all.ps1"
}

# Step 1: Apply configurations (fast)
Write-Host "`n[1/5] Applying ConfigMaps..." -ForegroundColor Yellow
kubectl apply -f "$PSScriptRoot\..\kafka-spark-configmap.yaml" | Out-Null
kubectl apply -f "$PSScriptRoot\..\expose-services.yaml" 2>$null | Out-Null
Write-Host "  ConfigMaps applied" -ForegroundColor Green

# Step 2: Build Docker image (skip if -SkipBuild)
if (-not $SkipBuild) {
    $existingImage = docker images steam-producer:latest --format "{{.Repository}}:{{.Tag}}" 2>$null
    if ($existingImage -eq "steam-producer:latest") {
        Write-Host "`n[2/5] Docker image exists (use -SkipBuild to always skip)" -ForegroundColor Green
    } else {
        Write-Host "`n[2/5] Building Docker image..." -ForegroundColor Yellow
        Push-Location "$PSScriptRoot\.."
        docker build -t steam-producer:latest . 2>&1 | Out-Null
        Pop-Location
        Write-Host "  Docker image built" -ForegroundColor Green
    }
} else {
    Write-Host "`n[2/5] Skipping Docker build (-SkipBuild flag)" -ForegroundColor Gray
}

# Step 3: Delete old Spark apps (for clean restart)
Write-Host "`n[3/5] Restarting Spark apps..." -ForegroundColor Yellow
kubectl delete sparkapplication steam-charts-app steam-reviews-app --ignore-not-found 2>$null | Out-Null
Start-Sleep -Seconds 2

# Step 4: Deploy Spark apps
kubectl apply -f "$PSScriptRoot\..\steam-charts-app.yaml" 2>$null | Out-Null
kubectl apply -f "$PSScriptRoot\..\steam-reviews-app.yaml" 2>$null | Out-Null
Write-Host "  Spark apps deployed" -ForegroundColor Green

# Step 5: Wait for drivers
Write-Host "`n[4/5] Waiting for Spark drivers (30s timeout)..." -ForegroundColor Yellow
$timeout = 30
$elapsed = 0
while ($elapsed -lt $timeout) {
    $drivers = kubectl get pods -l spark-role=driver --no-headers 2>$null | Select-String "Running"
    $driverCount = ($drivers | Measure-Object).Count
    if ($driverCount -ge 1) {
        Write-Host "  Spark driver(s) running ($driverCount)" -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 5
    $elapsed += 5
    Write-Host "  Waiting... ($elapsed s)" -ForegroundColor Gray
}

# Step 6: Show access URLs
Write-Host "`n[5/5] Service URLs:" -ForegroundColor Yellow
Write-Host "  Spark UI:    http://localhost:30040 (after port-forward or NodePort)" -ForegroundColor Cyan
Write-Host "  Grafana:     http://localhost:30300" -ForegroundColor Cyan
Write-Host "  Prometheus:  http://localhost:30090" -ForegroundColor Cyan
Write-Host "  MongoDB:     kubectl port-forward svc/mongodb 27017:27017" -ForegroundColor Cyan

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  Quick deploy complete! " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  - Run producer: kubectl apply -f steam-job.yaml" -ForegroundColor Gray
Write-Host "  - View Spark logs: kubectl logs -l spark-role=driver -f" -ForegroundColor Gray
Write-Host "  - Full E2E test: .\test\test-e2e-pipeline.ps1" -ForegroundColor Gray
