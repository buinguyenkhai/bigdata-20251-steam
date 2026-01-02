import time
import json
import re
import html
import requests
import os
from datetime import datetime
from confluent_kafka import Producer

# ==============================================================================
# CONFIGURATION & ENV VARS
# ==============================================================================
BOOTSTRAP_SERVERS = os.getenv("BOOTSTRAP_SERVERS", "localhost:9092")
TOPIC_GAME_INFO = os.getenv("TOPIC_GAME_INFO", "game_info")
TOPIC_GAME_COMMENTS = os.getenv("TOPIC_GAME_COMMENTS", "game_comments")
TOPIC_PLAYER_COUNT = os.getenv("TOPIC_PLAYER_COUNT", "game_player_count")

# SSL/TLS configuration
KAFKA_SECURITY_PROTOCOL = os.getenv("KAFKA_SECURITY_PROTOCOL", "PLAINTEXT")
KAFKA_SSL_CA_LOCATION = os.getenv("KAFKA_SSL_CA_LOCATION", "")
KAFKA_SSL_TRUSTSTORE_LOCATION = os.getenv("KAFKA_SSL_TRUSTSTORE_LOCATION", "")

# Genre Map from review_scrape.py
GENRE_TAG_MAP = {
    "sports": 701, "horror": 1667, "science_fiction": 3942,
    "exploration_open_world": 1695, "anime": 4085, "survival": 1662,
    "action_fps": 1663, "hidden_object": 1738, "rpg_action": 4231,
    "casual": 597, "puzzle_matching": 1664, "visual_novel": 3799
}

# ==============================================================================
# KAFKA PRODUCER SETUP
# ==============================================================================
producer_conf = {
    "bootstrap.servers": BOOTSTRAP_SERVERS,
    "client.id": "steam-producer-unified",
    "linger.ms": 5,
}

if KAFKA_SECURITY_PROTOCOL == "SSL":
    producer_conf["security.protocol"] = "SSL"
    producer_conf["ssl.endpoint.identification.algorithm"] = "none"
    producer_conf["enable.ssl.certificate.verification"] = "false"
    if KAFKA_SSL_CA_LOCATION:
        producer_conf["ssl.ca.location"] = KAFKA_SSL_CA_LOCATION
    if KAFKA_SSL_TRUSTSTORE_LOCATION:
        producer_conf["ssl.truststore.location"] = KAFKA_SSL_TRUSTSTORE_LOCATION

producer = Producer(producer_conf)

delivery_stats = {"success": 0, "failed": 0, "last_error": None}
MAX_DELIVERY_FAILURES = 100

# ==============================================================================
# UTILITIES
# ==============================================================================
def print_log(*args):
    print(f"[{str(datetime.now())[:-3]}] ", end="")
    print(*args)

def clean_html(raw_html):
    """Cleans HTML tags from text (from review_scrape.py)."""
    if not raw_html: return ""
    cleanr = re.compile('<.*?>')
    return html.unescape(re.sub(cleanr, '', raw_html)).strip()

def delivery_report(err, msg):
    """Callback for Kafka message delivery."""
    global delivery_stats
    if err is not None:
        delivery_stats["failed"] += 1
        delivery_stats["last_error"] = str(err)
        print_log(f"Delivery failed: {err}")
    else:
        delivery_stats["success"] += 1

def kafka_send(topic: str, value: dict, key: str = None):
    """Send dict as JSON to Kafka."""
    try:
        payload = json.dumps(value, default=str, ensure_ascii=False)
        producer.produce(topic, key=key, value=payload, callback=delivery_report)
        producer.poll(0)
    except Exception as e:
        print_log(f"Failed to produce message to {topic}:", e)

# ==============================================================================
# API FETCHING FUNCTIONS
# ==============================================================================
def get_search_results(params, max_retries=3):
    """Fetches search results from Steam."""
    url = "https://store.steampowered.com/search/results/"
    for attempt in range(1, max_retries + 1):
        try:
            r = requests.get(url, params=params, timeout=15)
            if r.status_code == 200:
                return r.json()
            elif r.status_code == 429:
                time.sleep(2 * attempt)
            else:
                return {"items": []}
        except Exception as e:
            print_log(f"Search error: {e}")
            time.sleep(1 * attempt)
    return {"items": []}

def get_app_details(appid):
    """Fetches detailed metadata for an AppID."""
    if not appid: return {}
    url = "https://store.steampowered.com/api/appdetails/"
    try:
        r = requests.get(url, params={"appids": appid, "cc": "us", "l": "english"}, timeout=20)
        if r.status_code == 200:
            return r.json().get(str(appid), {})
        elif r.status_code == 429:
            time.sleep(5)
    except Exception as e:
        print_log(f"App details error for {appid}: {e}")
    return {}

def get_current_players(appid):
    """Fetches current player count (from player_count.py)."""
    url = "https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/"
    try:
        r = requests.get(url, params={'appid': appid}, timeout=10)
        if r.status_code == 200:
            return r.json().get('response', {}).get('player_count', 0)
    except Exception as e:
        print_log(f"Player count error for {appid}: {e}")
    return -1

def fetch_steam_reviews(app_id, max_pages=3):
    """
    Fetches RECENT reviews without balancing.
    Yields cleaned review objects.
    """
    base_url = f"https://store.steampowered.com/appreviews/{app_id}"
    cursor = "*"
    
    for page in range(max_pages):
        params = {
            "json": 1,
            "filter": "recent", # Using recent to get latest stream of data
            "language": "english",
            "review_type": "all",
            "purchase_type": "all",
            "num_per_page": 100,
            "cursor": cursor,
        }
        try:
            resp = requests.get(base_url, params=params, timeout=20)
            if resp.status_code != 200: break
            data = resp.json()
        except: break

        reviews = data.get("reviews", [])
        if not reviews: break

        for r in reviews:
            yield {
                "app_id": app_id,
                "review_id": r.get("recommendationid"),
                "author_steamid": r.get("author", {}).get("steamid"),
                "playtime_at_review": r.get("author", {}).get("playtime_at_review"),
                "playtime_forever": r.get("author", {}).get("playtime_forever"),
                "language": r.get("language"),
                "voted_up": r.get("voted_up"),
                "votes_up": r.get("votes_up"),
                "weighted_vote_score": r.get("weighted_vote_score"),
                "timestamp_created": r.get("timestamp_created"),
                "review_text": clean_html(r.get("review")), # Cleaned HTML
                "scraped_at": datetime.utcnow().isoformat()
            }

        cursor = data.get("cursor", "")
        if not cursor: break
        time.sleep(0.5)

# ==============================================================================
# DATA PROCESSING
# ==============================================================================
def flatten_app_data(item, genre_tag):
    """
    Flattens app details for the 'game_info' topic.
    Combines logic from all_scrape.py and steam_to_kafka.py.
    """
    appid = item.get("appid")
    appdetail = item.get("appdetail", {})
    data = appdetail.get("data", {}) if isinstance(appdetail, dict) else {}
    
    # Serialize complex fields to string for Spark/DB compatibility
    return {
        "appid": int(appid),
        "name": item.get("name"),
        "primary_genre": genre_tag, # From loop context
        "type": data.get("type"),
        "release_date": data.get("release_date", {}).get("date"),
        "is_free": data.get("is_free"),
        "short_description": clean_html(data.get("short_description")),
        "developers": json.dumps(data.get("developers") or []),
        "publishers": json.dumps(data.get("publishers") or []),
        "genres": json.dumps([g.get("description") for g in (data.get("genres") or [])]),
        "price_overview": json.dumps(data.get("price_overview") or {}),
        "categories": json.dumps([c.get("description") for c in (data.get("categories") or [])]),
        "metacritic": data.get("metacritic", {}).get("score"),
        "recommendations": data.get("recommendations", {}).get("total"),
        "achievements_count": data.get("achievements", {}).get("total", 0),
        "timestamp_scraped": datetime.utcnow().isoformat()
    }

def process_genres_and_send():
    """
    Main Logic: Iterates genres -> Gets Top 10 -> Sends Info, Players, Reviews to Kafka.
    """
    processed_appids = set()

    for genre_name, tag_id in GENRE_TAG_MAP.items():
        print_log(f"--- Processing Genre: {genre_name} (Tag: {tag_id}) ---")
        
        # 1. Fetch Top Games for Genre
        # category1=998 ensures we get "Games" and not DLC/Music
        params = {
            "tags": tag_id, 
            "category1": 998, 
            "json": 1, 
            "page": 1  # We only need the first batch to get top 10
        }
        
        sr = get_search_results(params)
        items = sr.get("items", [])
        
        games_processed_for_genre = 0
        target_per_genre = 1
        
        for item in items:
            if games_processed_for_genre >= target_per_genre:
                break
                
            # Extract AppID
            try:
                logo = item.get("logo", "")
                if "steam/" in logo:
                    appid = re.search(r"steam/\w+/(\d+)", logo).group(1)
                else: 
                    # Fallback if logo URL format differs
                    appid = item.get("id") # Sometimes present in search results
            except: appid = None

            if not appid or appid in processed_appids:
                continue

            print_log(f"  > Processing: {item.get('name')} (AppID: {appid})")
            
            # 2. Fetch Details & Send Game Info
            appdetails = get_app_details(appid)
            if not appdetails.get("success"):
                print_log("    Failed to get app details, skipping.")
                continue
                
            item["appid"] = appid
            item["appdetail"] = appdetails
            
            game_record = flatten_app_data(item, genre_name)
            kafka_send(TOPIC_GAME_INFO, game_record, key=str(appid))
            
            # 3. Fetch & Send Player Count
            p_count = get_current_players(appid)
            if p_count >= 0:
                player_record = {
                    "appid": int(appid),
                    "player_count": p_count,
                    "timestamp": datetime.utcnow().isoformat()
                }
                kafka_send(TOPIC_PLAYER_COUNT, player_record, key=str(appid))
                print_log(f"    Sent player count: {p_count}")

            # 4. Fetch & Send Reviews (Recent, Unbalanced)
            review_count = 0
            for review in fetch_steam_reviews(appid, max_pages=3):
                kafka_send(TOPIC_GAME_COMMENTS, review, key=str(appid))
                review_count += 1
            print_log(f"    Sent {review_count} reviews.")

            # Mark processed
            processed_appids.add(appid)
            games_processed_for_genre += 1
            
            # Respect rate limits
            time.sleep(1.5)

    producer.flush()
    print_log("Done. Producer flushed.")

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
if __name__ == "__main__":
    print_log("Starting Steam Unified Scraper -> Kafka")
    print_log(f"  Topics: {TOPIC_GAME_INFO}, {TOPIC_GAME_COMMENTS}, {TOPIC_PLAYER_COUNT}")

    # Verify connection
    try:
        producer.list_topics(timeout=10)
        print_log("  Kafka connection successful.")
    except Exception as e:
        print_log(f"  ERROR: Could not connect to Kafka: {e}")
        exit(1)

    try:
        process_genres_and_send()
    except KeyboardInterrupt:
        print_log("Interrupted.")
    except Exception as e:
        print_log(f"Fatal Error: {e}")
    finally:
        producer.flush()