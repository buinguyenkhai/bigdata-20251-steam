// MongoDB Index Setup Script for Steam Analytics
// Run with: kubectl exec -it <mongodb-pod> -- mongosh game_analytics < mongodb-indexes.js
// Or paste into mongosh shell

// Switch to the database
db = db.getSiblingDB('game_analytics');

print("=== Creating indexes for steam_reviews collection ===");

// 1. TTL Index on timestamp for hot storage management (30 days retention)
// This also serves as the timestamp index for time-based queries
// Adjust expireAfterSeconds based on your retention needs:
// - 30 days = 2592000 seconds
// - 7 days = 604800 seconds
// - 90 days = 7776000 seconds
db.steam_reviews.createIndex(
    { "timestamp": 1 },
    {
        name: "idx_timestamp_ttl",
        expireAfterSeconds: 2592000,  // 30 days
        background: true
    }
);
print("✓ Created TTL index on timestamp (30 days retention)");

// 2. Compound index for app_id + timestamp (frequent query pattern)
db.steam_reviews.createIndex(
    { "app_id": 1, "timestamp": 1 },
    { name: "idx_appid_timestamp", background: true }
);
print("✓ Created app_id + timestamp compound index");

// 3. Weighted vote score index for sorting/ranking queries
db.steam_reviews.createIndex(
    { "weighted_vote_score": -1 },
    { name: "idx_weighted_vote_score", background: true }
);

print("\n=== Creating indexes for steam_charts collection ===");

// 5. Type index for chart type filtering
db.steam_charts.createIndex(
    { "type": 1 },
    { name: "idx_type", background: true }
);
print("✓ Created type index");

// 6. Compound index for type + timestamp queries
db.steam_charts.createIndex(
    { "type": 1, "timestamp": 1 },
    { name: "idx_type_timestamp", background: true }
);
print("✓ Created type + timestamp compound index");

print("\n=== Verifying indexes ===");
print("steam_reviews indexes:");
printjson(db.steam_reviews.getIndexes());

print("\nsteam_charts indexes:");
printjson(db.steam_charts.getIndexes());

print("\n=== Index setup complete! ===");
