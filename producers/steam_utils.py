import os
import time
import json
import re
import html
import requests
from datetime import datetime
from confluent_kafka import Producer

# ==============================================================================
# CONFIGURATION & ENV VARS
# ==============================================================================
BOOTSTRAP_SERVERS = os.getenv("BOOTSTRAP_SERVERS", "localhost:9092")

# Topics
TOPIC_GAME_INFO = os.getenv("TOPIC_GAME_INFO", "game_info")
TOPIC_GAME_COMMENTS = os.getenv("TOPIC_GAME_COMMENTS", "game_comments")
TOPIC_PLAYER_COUNT = os.getenv("TOPIC_PLAYER_COUNT", "game_player_count")

# SSL/TLS configuration
KAFKA_SECURITY_PROTOCOL = os.getenv("KAFKA_SECURITY_PROTOCOL", "PLAINTEXT")
KAFKA_SSL_CA_LOCATION = os.getenv("KAFKA_SSL_CA_LOCATION", "")
KAFKA_SSL_TRUSTSTORE_LOCATION = os.getenv("KAFKA_SSL_TRUSTSTORE_LOCATION", "")

# Scraper Configuration
# Defaults to a large number (essentially all) if not set, or user can limit via Env Var
MAX_APPS_TO_PROCESS = int(os.getenv("MAX_APPS_TO_PROCESS", "10")) 
# Controls depth of review scraping
MAX_REVIEW_PAGES = int(os.getenv("MAX_REVIEW_PAGES", "3"))

# ==============================================================================
# LOGGING & UTILS
# ==============================================================================
def print_log(*args):
    print(f"[{str(datetime.now())[:-3]}] ", end="")
    print(*args)

def clean_html(raw_html):
    """Cleans HTML tags from text."""
    if not raw_html: return ""
    cleanr = re.compile('<.*?>')
    return html.unescape(re.sub(cleanr, '', raw_html)).strip()

def read_processed_appids(filepath="processed_appids.txt"):
    """Reads AppIDs from a local text file, one per line."""
    if not os.path.exists(filepath):
        print_log(f"WARNING: {filepath} not found. Returning empty list.")
        return []
    
    appids = []
    with open(filepath, 'r') as f:
        for line in f:
            clean_line = line.strip()
            if clean_line and clean_line.isdigit():
                appids.append(clean_line)
    
    print_log(f"Loaded {len(appids)} AppIDs from {filepath}.")
    return appids

# ==============================================================================
# KAFKA PRODUCER
# ==============================================================================
def setup_producer():
    """Initializes and returns a Confluent Kafka Producer."""
    producer_conf = {
        "bootstrap.servers": BOOTSTRAP_SERVERS,
        "client.id": f"steam-producer-{os.getenv('HOSTNAME', 'local')}",
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
    
    print_log("Initializing Kafka Producer...")
    return Producer(producer_conf)

def delivery_report(err, msg):
    """Callback for Kafka message delivery."""
    if err is not None:
        print_log(f"Delivery failed for record {msg.key()}: {err}")
    # else:
    #     print_log(f"Record {msg.key()} produced to {msg.topic()} [{msg.partition()}] @ {msg.offset()}")

def kafka_send(producer, topic, value, key=None):
    """Send dict as JSON to Kafka using the provided producer."""
    try:
        payload = json.dumps(value, default=str, ensure_ascii=False)
        producer.produce(topic, key=key, value=payload, callback=delivery_report)
        producer.poll(0)
    except Exception as e:
        print_log(f"Failed to produce message to {topic}:", e)

# ==============================================================================
# STEAM API FETCHING
# ==============================================================================
def get_app_details(appid):
    """Fetches detailed metadata for an AppID."""
    if not appid: return {}
    url = "https://store.steampowered.com/api/appdetails/"
    try:
        r = requests.get(url, params={"appids": appid, "cc": "us", "l": "english"}, timeout=20)
        if r.status_code == 200:
            return r.json().get(str(appid), {})
        elif r.status_code == 429:
            print_log(f"Rate limited (429) fetching details for {appid}. Sleeping 5s...")
            time.sleep(5)
    except Exception as e:
        print_log(f"App details error for {appid}: {e}")
    return {}

def get_current_players(appid):
    """Fetches current player count."""
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
            "filter": "recent",
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
                "review_text": clean_html(r.get("review")),
                "scraped_at": datetime.utcnow().isoformat()
            }

        cursor = data.get("cursor", "")
        if not cursor: break
        time.sleep(0.5)

def flatten_app_data(item, genre_tag=None):
    """
    Flattens app details for the 'game_info' topic.
    """
    appid = item.get("appid")
    appdetail = item.get("appdetail", {})
    data = appdetail.get("data", {}) if isinstance(appdetail, dict) else {}
    
    return {
        "appid": int(appid),
        "name": item.get("name") or data.get("name"), # Fallback to detail name
        "primary_genre": genre_tag,
        "type": data.get("type"),
        "release_date": data.get("release_date", {}).get("date"),
        "is_free": data.get("is_free"),
        "short_description": clean_html(data.get("short_description")),
        "developers": data.get("developers") or [],
        "publishers": data.get("publishers") or [],
        "genres": [g.get("description") for g in (data.get("genres") or [])],
        "price_overview": data.get("price_overview") or {},
        "categories": [c.get("description") for c in (data.get("categories") or [])],
        "metacritic": data.get("metacritic", {}).get("score"),
        "recommendations": data.get("recommendations", {}).get("total"),
        "achievements_count": data.get("achievements", {}).get("total", 0),
        "timestamp_scraped": datetime.utcnow().isoformat()
    }
