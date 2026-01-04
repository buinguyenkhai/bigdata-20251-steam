// ╔═══════════════════════════════════════════════════════════════╗
// ║         Steam Analytics - Demo Queries for Presentation       ║
// ║                                                               ║
// ║  Run: kubectl exec -it <mongodb-pod> -- mongosh bigdata       ║
// ║       < demo-queries.js                                       ║
// ╚═══════════════════════════════════════════════════════════════╝

db = db.getSiblingDB('bigdata');

// ═══════════════════════════════════════════════════════════════════
// DEMO QUERY 1: Review Statistics Over Time
// Purpose: Show review trends and sentiment over hourly windows
// Collection: steam_reviews
// ═══════════════════════════════════════════════════════════════════
print("\n");
print("╔═══════════════════════════════════════════════════════════════╗");
print("║  QUERY 1: Review Statistics Over Time                        ║");
print("╚═══════════════════════════════════════════════════════════════╝");
print("Collection: steam_reviews");
print("Description: Aggregated review data with sentiment and quality scores\n");

let reviewStats = db.steam_reviews.aggregate([
    {
        $project: {
            time_window: {
                $concat: [
                    { $dateToString: { format: "%Y-%m-%d %H:%M", date: "$window.start" } },
                    " → ",
                    { $dateToString: { format: "%H:%M", date: "$window.end" } }
                ]
            },
            sentiment: { $cond: ["$recommended", "👍 Positive", "👎 Negative"] },
            total_reviews: 1,
            avg_quality: { $round: ["$avg_quality", 3] }
        }
    },
    { $sort: { "window.start": -1 } },
    { $limit: 10 }
]).toArray();

if (reviewStats.length > 0) {
    print("Latest 10 Review Windows:");
    print("─────────────────────────────────────────────────────────────────");
    reviewStats.forEach((doc, i) => {
        print(`${i + 1}. ${doc.time_window}`);
        print(`   ${doc.sentiment} | Reviews: ${doc.total_reviews} | Avg Quality: ${doc.avg_quality}`);
    });
} else {
    print("⚠️  No review data found. Run the pipeline to ingest data.");
}


// ═══════════════════════════════════════════════════════════════════
// DEMO QUERY 2: Top Game Genres (Steam Charts)
// Purpose: Show the most popular genres by game count
// Collection: steam_charts
// ═══════════════════════════════════════════════════════════════════
print("\n");
print("╔═══════════════════════════════════════════════════════════════╗");
print("║  QUERY 2: Top Game Genres                                     ║");
print("╚═══════════════════════════════════════════════════════════════╝");
print("Collection: steam_charts");
print("Description: Genre popularity based on game count\n");

let topGenres = db.steam_charts.find()
    .sort({ total_games: -1 })
    .limit(10)
    .toArray();

if (topGenres.length > 0) {
    print("Top 10 Genres by Game Count:");
    print("─────────────────────────────────────────────────────────────────");

    // Create a simple bar chart
    let maxGames = topGenres[0].total_games || 1;
    topGenres.forEach((doc, i) => {
        let barLength = Math.round((doc.total_games / maxGames) * 30);
        let bar = "█".repeat(barLength) + "░".repeat(30 - barLength);
        print(`${String(i + 1).padStart(2)}. ${doc.genre.padEnd(20)} ${bar} ${doc.total_games}`);
    });
} else {
    print("⚠️  No genre data found. Run the pipeline to ingest data.");
}


// ═══════════════════════════════════════════════════════════════════
// DEMO QUERY 3: Player Count Trends
// Purpose: Show player activity across games over time
// Collection: steam_players
// ═══════════════════════════════════════════════════════════════════
print("\n");
print("╔═══════════════════════════════════════════════════════════════╗");
print("║  QUERY 3: Player Count Trends                                 ║");
print("╚═══════════════════════════════════════════════════════════════╝");
print("Collection: steam_players");
print("Description: Player count analytics per game (10-min windows)\n");

let playerTrends = db.steam_players.aggregate([
    {
        $group: {
            _id: "$appid",
            total_windows: { $sum: 1 },
            overall_avg_players: { $avg: "$avg_players" },
            peak_players: { $max: "$max_players" },
            latest_window: { $max: "$window.end" }
        }
    },
    { $sort: { peak_players: -1 } },
    { $limit: 10 }
]).toArray();

if (playerTrends.length > 0) {
    print("Top 10 Games by Peak Player Count:");
    print("─────────────────────────────────────────────────────────────────");
    print("App ID     │ Peak Players │ Avg Players │ Windows");
    print("───────────┼──────────────┼─────────────┼─────────");
    playerTrends.forEach(doc => {
        let appId = String(doc._id).padEnd(10);
        let peak = String(doc.peak_players).padStart(12);
        let avg = doc.overall_avg_players.toFixed(1).padStart(11);
        let windows = String(doc.total_windows).padStart(7);
        print(`${appId} │ ${peak} │ ${avg} │ ${windows}`);
    });
} else {
    print("⚠️  No player data found. Run the pipeline to ingest data.");
}


// ═══════════════════════════════════════════════════════════════════
// DEMO QUERY 4: Review Sentiment Distribution
// Purpose: Analyze overall sentiment (positive vs negative reviews)
// Collection: steam_reviews
// ═══════════════════════════════════════════════════════════════════
print("\n");
print("╔═══════════════════════════════════════════════════════════════╗");
print("║  QUERY 4: Review Sentiment Distribution                       ║");
print("╚═══════════════════════════════════════════════════════════════╝");
print("Collection: steam_reviews");
print("Description: Overall positive vs negative review analysis\n");

let sentimentDist = db.steam_reviews.aggregate([
    {
        $group: {
            _id: "$recommended",
            total_windows: { $sum: 1 },
            total_reviews: { $sum: "$total_reviews" },
            avg_quality: { $avg: "$avg_quality" }
        }
    },
    { $sort: { _id: -1 } }  // true (positive) first
]).toArray();

if (sentimentDist.length > 0) {
    print("Sentiment Breakdown:");
    print("─────────────────────────────────────────────────────────────────");

    let totalReviews = sentimentDist.reduce((sum, d) => sum + d.total_reviews, 0);

    sentimentDist.forEach(doc => {
        let sentiment = doc._id ? "👍 Positive (Recommended)" : "👎 Negative (Not Recommended)";
        let percentage = ((doc.total_reviews / totalReviews) * 100).toFixed(1);
        let barLength = Math.round(percentage / 100 * 40);
        let bar = "█".repeat(barLength) + "░".repeat(40 - barLength);

        print(`\n${sentiment}`);
        print(`   Reviews: ${doc.total_reviews} (${percentage}%)`);
        print(`   ${bar}`);
        print(`   Avg Quality Score: ${doc.avg_quality.toFixed(3)}`);
    });
} else {
    print("⚠️  No sentiment data found. Run the pipeline to ingest data.");
}


// ═══════════════════════════════════════════════════════════════════
// DEMO QUERY 5: Real-Time Activity Summary
// Purpose: Combined stats from all collections for dashboard overview
// Collection: All (steam_reviews, steam_charts, steam_players)
// ═══════════════════════════════════════════════════════════════════
print("\n");
print("╔═══════════════════════════════════════════════════════════════╗");
print("║  QUERY 5: Real-Time Activity Summary                          ║");
print("╚═══════════════════════════════════════════════════════════════╝");
print("Collections: All");
print("Description: Combined dashboard statistics\n");

// Gather stats from all collections
let reviewCount = db.steam_reviews.countDocuments();
let chartsCount = db.steam_charts.countDocuments();
let playersCount = db.steam_players.countDocuments();

// Get latest activity timestamps
let latestReview = db.steam_reviews.findOne({}, { sort: { "window.end": -1 } });
let latestPlayer = db.steam_players.findOne({}, { sort: { "window.end": -1 } });

// Calculate totals
let totalReviews = db.steam_reviews.aggregate([
    { $group: { _id: null, total: { $sum: "$total_reviews" } } }
]).toArray();

let totalGames = db.steam_charts.aggregate([
    { $group: { _id: null, total: { $sum: "$total_games" } } }
]).toArray();

let peakPlayers = db.steam_players.aggregate([
    { $group: { _id: null, peak: { $max: "$max_players" } } }
]).toArray();

print("╔═════════════════════════════════════════════════════════════╗");
print("║                  STEAM ANALYTICS DASHBOARD                   ║");
print("╠═════════════════════════════════════════════════════════════╣");

print("║  📊 Data Volume                                              ║");
print("║  ─────────────────────────────────────────────────────────  ║");
print(`║    Reviews Windows:     ${String(reviewCount).padStart(10)}                       ║`);
print(`║    Genre Records:       ${String(chartsCount).padStart(10)}                       ║`);
print(`║    Player Windows:      ${String(playersCount).padStart(10)}                       ║`);

print("║                                                              ║");
print("║  📈 Key Metrics                                              ║");
print("║  ─────────────────────────────────────────────────────────  ║");

let reviewTotal = totalReviews.length > 0 ? totalReviews[0].total : 0;
let gamesTotal = totalGames.length > 0 ? totalGames[0].total : 0;
let playerPeak = peakPlayers.length > 0 ? peakPlayers[0].peak : 0;

print(`║    Total Reviews:       ${String(reviewTotal).padStart(10)}                       ║`);
print(`║    Total Games Tracked: ${String(gamesTotal).padStart(10)}                       ║`);
print(`║    Peak Concurrent:     ${String(playerPeak).padStart(10)} players               ║`);

print("║                                                              ║");
print("║  🕐 Latest Activity                                          ║");
print("║  ─────────────────────────────────────────────────────────  ║");

if (latestReview && latestReview.window) {
    let reviewTime = latestReview.window.end ? latestReview.window.end.toISOString() : "N/A";
    print(`║    Last Review Window:  ${reviewTime.substring(0, 19)}            ║`);
}

if (latestPlayer && latestPlayer.window) {
    let playerTime = latestPlayer.window.end ? latestPlayer.window.end.toISOString() : "N/A";
    print(`║    Last Player Window:  ${playerTime.substring(0, 19)}            ║`);
}

print("╚═════════════════════════════════════════════════════════════╝");

print("\n═══════════════════════════════════════════════════════════════");
print("                    Demo Queries Complete!                      ");
print("═══════════════════════════════════════════════════════════════\n");
