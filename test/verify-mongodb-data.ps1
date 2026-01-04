# MongoDB Data Verification Script for Steam Analytics
# This script verifies data in all 3 MongoDB collections

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       MongoDB Data Verification - Steam Analytics             ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Get the MongoDB pod name
$mongoPod = kubectl get pods -l app=mongodb -o jsonpath='{.items[0].metadata.name}' 2>$null

if (-not $mongoPod) {
    Write-Host "ERROR: MongoDB pod not found!" -ForegroundColor Red
    Write-Host "Make sure the pipeline is deployed: .\test\test-e2e-pipeline.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found MongoDB pod: $mongoPod" -ForegroundColor Green
Write-Host ""

# Check each collection (all in game_analytics database)
$collections = @("steam_reviews", "steam_charts", "steam_players")
$results = @{}

foreach ($collection in $collections) {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "📊 Checking collection: $collection" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    
    # Get document count
    $countCmd = "db.$collection.countDocuments()"
    $rawCount = kubectl exec $mongoPod -- mongosh game_analytics --quiet --eval $countCmd 2>$null
    
    # Clean output to get just numbers
    $count = 0
    if ($rawCount -match '(\d+)') {
        $count = [int]$matches[1]
    }
    
    $results[$collection] = $count
    
    if ($count -gt 0) {
        Write-Host "  ✅ Document Count: $count" -ForegroundColor Green
        
        # Get sample document
        Write-Host "  📝 Sample Document:" -ForegroundColor Cyan
        $sampleCmd = "JSON.stringify(db.$collection.findOne(), null, 2)"
        $sample = kubectl exec $mongoPod -- mongosh game_analytics --quiet --eval $sampleCmd 2>$null
        # Truncate if too long for display
        if ($sample.Length -gt 1000) { $sample = $sample.Substring(0, 1000) + "... (truncated)" }
        Write-Host $sample -ForegroundColor Gray
    } else {
        Write-Host "  ⚠️  Collection is EMPTY" -ForegroundColor Yellow
    }
    Write-Host ""
}

# Summary
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    VERIFICATION SUMMARY                        ║" -ForegroundColor Cyan
Write-Host "╠═══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan

$totalDocs = 0
foreach ($collection in $collections) {
    $count = $results[$collection]
    $totalDocs += $count
    $status = if ($count -gt 0) { "✅ OK" } else { "⚠️  EMPTY" }
    
    # Format line manually to ensure alignment
    $colStr = $collection.PadRight(18)
    $countStr = "$count".PadRight(9)
    $line = "║  $colStr │ $countStr │ $status"
    
    if ($count -gt 0) {
        Write-Host $line -ForegroundColor Green
    } else {
        Write-Host $line -ForegroundColor Yellow
    }
}

Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($totalDocs -gt 0) {
    Write-Host "🎉 MongoDB has $totalDocs total documents across all collections!" -ForegroundColor Green
} else {
    Write-Host "⚠️  No data found! Make sure the pipeline is running:" -ForegroundColor Yellow
    Write-Host "   1. Run: .\test\test-e2e-pipeline.ps1" -ForegroundColor Gray
    Write-Host "   2. Wait for Spark jobs to process data" -ForegroundColor Gray
}

# Quick access
Write-Host ""
Write-Host "═══ Quick Access Commands ═══" -ForegroundColor Magenta
Write-Host "  Shell Access: kubectl exec -it $mongoPod -- mongosh game_analytics" -ForegroundColor Cyan
Write-Host "  Run Queries:  kubectl exec -it $mongoPod -- mongosh game_analytics < .\test\demo-queries.js" -ForegroundColor Cyan
