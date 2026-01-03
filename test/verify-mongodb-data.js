// MongoDB Data Verification Script for Steam Analytics
// Run with: kubectl exec -it <mongodb-pod> -- mongosh bigdata < verify-mongodb-data.js
// Or paste into mongosh shell

print("╔═══════════════════════════════════════════════════════════════╗");
print("║       MongoDB Data Verification - Steam Analytics             ║");
print("╚═══════════════════════════════════════════════════════════════╝\n");

// Switch to the database
db = db.getSiblingDB('bigdata');

// ==========================================
// 1. COLLECTION: steam_reviews
// ==========================================
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
print("📊 COLLECTION: steam_reviews");
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

let reviewsCount = db.steam_reviews.countDocuments();
print("Document Count: " + reviewsCount);

if (reviewsCount > 0) {
    print("\n✅ Collection has data!");
    print("\n📝 Sample Document:");
    printjson(db.steam_reviews.findOne());
    
    print("\n📈 Schema Fields:");
    let sampleReview = db.steam_reviews.findOne();
    if (sampleReview) {
        Object.keys(sampleReview).forEach(key => {
            let type = typeof sampleReview[key];
            if (sampleReview[key] instanceof Date) type = "Date";
            if (sampleReview[key] === null) type = "null";
            if (Array.isArray(sampleReview[key])) type = "Array";
            if (key === "window" && sampleReview[key]) type = "Object {start, end}";
            print("   • " + key + ": " + type);
        });
    }
    
    print("\n📊 Stats:");
    let positiveReviews = db.steam_reviews.countDocuments({ recommended: true });
    let negativeReviews = db.steam_reviews.countDocuments({ recommended: false });
    print("   • Positive reviews (recommended=true): " + positiveReviews);
    print("   • Negative reviews (recommended=false): " + negativeReviews);
} else {
    print("\n⚠️  Collection is EMPTY - no data ingested yet");
}

// ==========================================
// 2. COLLECTION: steam_charts
// ==========================================
print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
print("📊 COLLECTION: steam_charts");
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

let chartsCount = db.steam_charts.countDocuments();
print("Document Count: " + chartsCount);

if (chartsCount > 0) {
    print("\n✅ Collection has data!");
    print("\n📝 Sample Document:");
    printjson(db.steam_charts.findOne());
    
    print("\n📈 Top 5 Genres by Game Count:");
    db.steam_charts.find().sort({ total_games: -1 }).limit(5).forEach(doc => {
        print("   • " + doc.genre + ": " + doc.total_games + " games");
    });
} else {
    print("\n⚠️  Collection is EMPTY - no data ingested yet");
}

// ==========================================
// 3. COLLECTION: steam_players
// ==========================================
print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
print("📊 COLLECTION: steam_players");
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

let playersCount = db.steam_players.countDocuments();
print("Document Count: " + playersCount);

if (playersCount > 0) {
    print("\n✅ Collection has data!");
    print("\n📝 Sample Document:");
    printjson(db.steam_players.findOne());
    
    print("\n📈 Schema Fields:");
    let samplePlayer = db.steam_players.findOne();
    if (samplePlayer) {
        Object.keys(samplePlayer).forEach(key => {
            let type = typeof samplePlayer[key];
            if (samplePlayer[key] instanceof Date) type = "Date";
            if (samplePlayer[key] === null) type = "null";
            if (Array.isArray(samplePlayer[key])) type = "Array";
            if (key === "window" && samplePlayer[key]) type = "Object {start, end}";
            print("   • " + key + ": " + type);
        });
    }
    
    print("\n📊 Stats:");
    let pipeline = [
        { $group: { _id: null, avgPlayers: { $avg: "$avg_players" }, maxPlayers: { $max: "$max_players" } } }
    ];
    let stats = db.steam_players.aggregate(pipeline).toArray();
    if (stats.length > 0) {
        print("   • Average player count: " + (stats[0].avgPlayers || 0).toFixed(2));
        print("   • Peak player count: " + (stats[0].maxPlayers || 0));
    }
} else {
    print("\n⚠️  Collection is EMPTY - no data ingested yet");
}

// ==========================================
// SUMMARY
// ==========================================
print("\n╔═══════════════════════════════════════════════════════════════╗");
print("║                    VERIFICATION SUMMARY                        ║");
print("╠═══════════════════════════════════════════════════════════════╣");
print("║  Collection        │ Documents │ Status                       ║");
print("╠═══════════════════════════════════════════════════════════════╣");

let reviewStatus = reviewsCount > 0 ? "✅ OK" : "⚠️  EMPTY";
let chartsStatus = chartsCount > 0 ? "✅ OK" : "⚠️  EMPTY";
let playersStatus = playersCount > 0 ? "✅ OK" : "⚠️  EMPTY";

print("║  steam_reviews     │ " + String(reviewsCount).padEnd(9) + " │ " + reviewStatus.padEnd(30) + "║");
print("║  steam_charts      │ " + String(chartsCount).padEnd(9) + " │ " + chartsStatus.padEnd(30) + "║");
print("║  steam_players     │ " + String(playersCount).padEnd(9) + " │ " + playersStatus.padEnd(30) + "║");
print("╚═══════════════════════════════════════════════════════════════╝");

let totalDocs = reviewsCount + chartsCount + playersCount;
if (totalDocs > 0) {
    print("\n🎉 MongoDB has " + totalDocs + " total documents across all collections!");
} else {
    print("\n⚠️  No data found! Make sure the pipeline is running:");
    print("   1. Run: .\\test\\test-e2e-pipeline.ps1");
    print("   2. Wait for Spark jobs to process data");
}
