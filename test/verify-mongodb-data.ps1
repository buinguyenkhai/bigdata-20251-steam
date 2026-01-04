# MongoDB Data Verification Script for Steam Analytics
# This script verifies data in all 3 MongoDB collections

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

# Function to run MongoDB command and get result
function Invoke-MongoCommand {
    param([string]$command)
    $result = kubectl exec $mongoPod -- mongosh bigdata --quiet --eval $command 2>$null
    return $result
}

# Check each collection
$collections = @("steam_reviews", "steam_charts", "steam_players")
$results = @{}

foreach ($collection in $collections) {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "📊 Checking collection: $collection" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    
    # Get document count
    $countCmd = "db.$collection.countDocuments()"
    $count = kubectl exec $mongoPod -- mongosh bigdata --quiet --eval $countCmd 2>$null
    $count = [int]($count -replace '\D', '')
    
    $results[$collection] = $count
    
    if ($count -gt 0) {
        Write-Host "  ✅ Document Count: $count" -ForegroundColor Green
        
        # Get sample document
        Write-Host "  📝 Sample Document:" -ForegroundColor Cyan
        $sampleCmd = "JSON.stringify(db.$collection.findOne(), null, 2)"
        $sample = kubectl exec $mongoPod -- mongosh bigdata --quiet --eval $sampleCmd 2>$null
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
    $line = "║  {0,-18} │ {1,-9} │ {2}" -f $collection, $count, $status
    
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

# Provide quick access commands
Write-Host ""
Write-Host "═══ Quick Access Commands ═══" -ForegroundColor Magenta
Write-Host "  Port Forward: kubectl port-forward svc/mongodb 27017:27017" -ForegroundColor Cyan
Write-Host "  Shell Access: kubectl exec -it $mongoPod -- mongosh bigdata" -ForegroundColor Cyan
Write-Host "  Run Queries:  kubectl exec -it $mongoPod -- mongosh bigdata < .\test\demo-queries.js" -ForegroundColor Cyan
