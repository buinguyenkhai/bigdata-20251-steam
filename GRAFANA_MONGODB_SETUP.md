# Grafana MongoDB Integration Guide

This guide helps connect MongoDB to Grafana for the Steam Analytics dashboards.

## Prerequisites

- Grafana running in the cluster
- MongoDB deployed and accessible
- Grafana MongoDB plugin installed

## Connection Configuration

### 1. Access Grafana

```powershell
# Port forward Grafana if not exposed
kubectl port-forward svc/grafana 3000:3000
```

Open http://localhost:3000 in your browser.

### 2. Add MongoDB Datasource

1. Go to **Configuration** → **Data Sources** → **Add data source**
2. Search for **MongoDB** and select **grafana-mongodb-opensource-datasource**

### 3. Configure Connection

| Setting | Value |
|---------|-------|
| **Name** | `Steam MongoDB` |
| **URL** | `mongodb://mongodb.default.svc.cluster.local:27017` |
| **Database** | `bigdata` |

> **Note:** If connecting from outside the cluster (via port-forward), use:
> - URL: `mongodb://localhost:27017` (after running `kubectl port-forward svc/mongodb 27017:27017`)

### 4. Test Connection

Click **Save & Test** to verify the connection.

---

## Collections Available

| Collection | Description | Key Fields |
|------------|-------------|------------|
| `steam_reviews` | Review analytics (1-hour windows) | `window`, `recommended`, `total_reviews`, `avg_quality` |
| `steam_charts` | Genre popularity | `genre`, `total_games` |
| `steam_players` | Player counts (10-min windows) | `window`, `appid`, `max_players`, `avg_players` |

---

## Sample Grafana Queries

### Query 1: Review Trends (Time Series)

```javascript
db.steam_reviews.aggregate([
  {
    "$project": {
      "time": "$window.start",
      "value": "$total_reviews",
      "__metric": { "$cond": ["$recommended", "Positive", "Negative"] },
      "_id": 0
    }
  },
  { "$sort": { "time": 1 } }
])
```

**Panel Type:** Time series

---

### Query 2: Top Genres (Bar Chart)

```javascript
db.steam_charts.aggregate([
  { "$sort": { "total_games": -1 } },
  { "$limit": 10 },
  {
    "$project": {
      "genre": 1,
      "value": "$total_games",
      "_id": 0
    }
  }
])
```

**Panel Type:** Bar chart / Stat

---

### Query 3: Player Count Trends (Time Series)

```javascript
db.steam_players.aggregate([
  {
    "$project": {
      "time": "$window.start",
      "value": "$max_players",
      "__metric": { "$toString": "$appid" },
      "_id": 0
    }
  },
  { "$sort": { "time": 1 } }
])
```

**Panel Type:** Time series

---

### Query 4: Sentiment Distribution (Pie Chart)

```javascript
db.steam_reviews.aggregate([
  {
    "$group": {
      "_id": "$recommended",
      "total": { "$sum": "$total_reviews" }
    }
  },
  {
    "$project": {
      "sentiment": { "$cond": ["$_id", "Positive", "Negative"] },
      "value": "$total",
      "_id": 0
    }
  }
])
```

**Panel Type:** Pie chart

---

### Query 5: Dashboard Stats (Stat Panels)

**Total Reviews:**
```javascript
db.steam_reviews.aggregate([
  { "$group": { "_id": null, "value": { "$sum": "$total_reviews" } } },
  { "$project": { "_id": 0 } }
])
```

**Peak Players:**
```javascript
db.steam_players.aggregate([
  { "$group": { "_id": null, "value": { "$max": "$max_players" } } },
  { "$project": { "_id": 0 } }
])
```

**Total Genres:**
```javascript
db.steam_charts.aggregate([
  { "$count": "value" }
])
```

---

## Troubleshooting

### Cannot connect to MongoDB

1. Verify MongoDB is running:
   ```powershell
   kubectl get pods -l app=mongodb
   ```

2. Check service exists:
   ```powershell
   kubectl get svc mongodb
   ```

3. Port forward for local access:
   ```powershell
   kubectl port-forward svc/mongodb 27017:27017
   ```

### No data showing in panels

1. Verify data exists:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\test\verify-mongodb-data.ps1
   ```

2. Run the pipeline to ingest data:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\test\test-e2e-pipeline.ps1
   ```

### Query returns empty

- Check the time range in Grafana (top right)
- Ensure `window.start` fields exist in your data
- Use the `demo-queries.js` script to verify data format

---

## Quick Commands Reference

```powershell
# Port forward MongoDB
kubectl port-forward svc/mongodb 27017:27017

# Access MongoDB shell
$mongoPod = kubectl get pods -l app=mongodb -o jsonpath='{.items[0].metadata.name}'
kubectl exec -it $mongoPod -- mongosh bigdata

# Run verification script
powershell -ExecutionPolicy Bypass -File .\test\verify-mongodb-data.ps1

# Run demo queries
kubectl exec -it $mongoPod -- mongosh bigdata < .\test\demo-queries.js
```
