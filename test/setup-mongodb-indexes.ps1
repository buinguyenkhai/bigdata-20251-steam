# MongoDB Index Setup Script
# This script applies indexes to the MongoDB instance running in Kubernetes

Write-Host "=== MongoDB Index Setup ===" -ForegroundColor Cyan

# Get the MongoDB pod name
$mongoPod = kubectl get pods -l app=mongodb -o jsonpath='{.items[0].metadata.name}'

if (-not $mongoPod) {
    Write-Host "ERROR: MongoDB pod not found!" -ForegroundColor Red
    exit 1
}

Write-Host "Found MongoDB pod: $mongoPod" -ForegroundColor Green

# Read the index script content
$scriptPath = Join-Path $PSScriptRoot "mongodb-indexes.js"
if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: mongodb-indexes.js not found at $scriptPath" -ForegroundColor Red
    exit 1
}

$scriptContent = Get-Content $scriptPath -Raw

# Execute the index script by piping content to mongosh
Write-Host "Executing index script..." -ForegroundColor Yellow
$scriptContent | kubectl exec -i $mongoPod -- mongosh game_analytics

Write-Host "`n=== Index Setup Complete ===" -ForegroundColor Cyan
