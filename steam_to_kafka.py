#!/usr/bin/env python3
"""
steam_to_kafka.py

Fetch Steam search/app details and reviews, send to Kafka topics:
 - game_info
 - game_comments

Uses confluent-kafka Producer.
"""

import time
import json
import re
from datetime import datetime
from pathlib import Path
import requests
from confluent_kafka import Producer
"""
# ---------- Configuration ----------
BOOTSTRAP_SERVERS = "localhost:9092"   # <-- change to your broker(s)
TOPIC_GAME_INFO = "game_info"
TOPIC_GAME_COMMENTS = "game_comments"
"""
import os

BOOTSTRAP_SERVERS = os.getenv("BOOTSTRAP_SERVERS", "localhost:9092")
TOPIC_GAME_INFO = os.getenv("TOPIC_GAME_INFO", "game_info")
TOPIC_GAME_COMMENTS = os.getenv("TOPIC_GAME_COMMENTS", "game_comments")

# Search params
PARAMS_SR_DEFAULT = {
    "filter": "topsellers",
    "hidef2p": 1,
    "page": 1,
    "json": 1
}

# Producer setup
producer_conf = {
    "bootstrap.servers": BOOTSTRAP_SERVERS,
    "client.id": "steam-producer",
    "linger.ms": 5,
    # increase retries if needed
}
producer = Producer(producer_conf)

def print_log(*args):
    print(f"[{str(datetime.now())[:-3]}] ", end="")
    print(*args)

def delivery_report(err, msg):
    if err is not None:
        print_log("Delivery failed:", err)
    # else:
    #     print_log(f"Delivered to {msg.topic()} [{msg.partition()}] at offset {msg.offset()}")

def kafka_send(topic: str, value: dict, key: str = None):
    """Send dict as JSON to Kafka."""
    try:
        payload = json.dumps(value, default=str, ensure_ascii=False)
        producer.produce(topic, key=key, value=payload, callback=delivery_report)
        producer.poll(0)
    except Exception as e:
        print_log("Failed to produce message:", e)

# ---------- Steam helpers ----------
def get_search_results(params, max_retries=3, backoff=2):
    url = "https://store.steampowered.com/search/results/"
    for attempt in range(1, max_retries + 1):
        try:
            r = requests.get(url, params=params, timeout=15)
            if r.status_code == 200:
                return r.json()
            elif r.status_code == 429:
                print_log("Rate limited by search endpoint. Sleeping...")
                time.sleep(backoff * attempt)
            else:
                print_log("Search returned status", r.status_code)
                return {"items": []}
        except Exception as e:
            print_log("Search request error:", e)
            time.sleep(backoff * attempt)
    return {"items": []}

def get_app_details(appid, max_retries=5):
    if not appid:
        return {}
    url = "https://store.steampowered.com/api/appdetails/"
    for attempt in range(1, max_retries + 1):
        try:
            r = requests.get(url, params={"appids": appid, "cc": "hk", "l": "english"}, timeout=20)
            if r.status_code == 200:
                jd = r.json().get(str(appid), {})
                print_log(f"App Id: {appid} - success={jd.get('success')}")
                return jd
            elif r.status_code == 429:
                print_log("App details rate limited. Sleeping 10s...")
                time.sleep(10)
            elif r.status_code == 403:
                print_log("Forbidden (403). Sleeping 300s...")
                time.sleep(300)
            else:
                print_log("App details HTTP", r.status_code)
                return {}
        except Exception as e:
            print_log("Error fetching app details:", e)
            time.sleep(2 ** attempt)
    return {}

def fetch_steam_reviews(app_id, max_pages=5, delay=1, start_date=None, end_date=None):
    """
    Fetch reviews (public) from Steam and yield each review record as dict.
    Based on Steam store appreviews endpoint and cursor paging.
    """
    base_url = f"https://store.steampowered.com/appreviews/{app_id}"
    cursor = "*"
    start_ts = None
    end_ts = None
    if start_date:
        start_ts = int(datetime.strptime(start_date, "%Y-%m-%d").timestamp())
    if end_date:
        end_ts = int(datetime.strptime(end_date, "%Y-%m-%d").timestamp())

    total = 0
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
            if resp.status_code != 200:
                print_log(f"Reviews endpoint returned {resp.status_code}. Stopping.")
                break
            data = resp.json()
        except Exception as e:
            print_log("Error fetching reviews:", e)
            break

        reviews = data.get("reviews", [])
        if not reviews:
            print_log("No reviews returned. Stopping.")
            break

        for r in reviews:
            ts = r.get("timestamp_created")
            if start_ts and ts < start_ts:
                continue
            if end_ts and ts > end_ts:
                continue

            review_rec = {
                "app_id": app_id,
                "review_id": r.get("recommendationid"),
                "author": r.get("author", {}).get("steamid"),
                "language": r.get("language"),
                "recommended": r.get("voted_up"),
                "steam_purchase": r.get("steam_purchase"),
                "votes_up": r.get("votes_up"),
                "weighted_vote_score": r.get("weighted_vote_score"),
                "timestamp_unix": ts,
                "timestamp": datetime.fromtimestamp(ts).isoformat() if ts else None,
                "review": r.get("review"),
                # include raw vote summary if present
                "votes_funny": r.get("votes_funny"),
            }
            total += 1
            yield review_rec

        cursor = data.get("cursor", "")
        if not cursor:
            break
        print_log(f"Fetched page {page+1} for app {app_id} - reviews so far: {total}")
        time.sleep(delay)

# ---------- Flatten / prepare game info ----------
def flatten_appdetail_record(item):
    """
    Build a reasonably compact JSON record for game_info. Keeps key nested fields as needed.
    We use appdetail.data as source (if present). The uploaded hierarchy lists many available fields (developers, genres, price_overview, platforms, release_date, etc).
    See uploaded hierarchy reference for full structure.
    """
    appdetail = item.get("appdetail", {})
    data = appdetail.get("data", {}) if isinstance(appdetail, dict) else {}

    rec = {
        "name": item.get("name"),
        "appid": int(item.get("appid")) if item.get("appid") else None,
        "type": data.get("type"),
        "short_description": data.get("short_description"),
        "developers": data.get("developers") or [],
        "publishers": data.get("publishers") or [],
        "genres": [g.get("description") for g in (data.get("genres") or [])],
        "price_overview": data.get("price_overview") or {},
        "platforms": data.get("platforms") or {},
        "header_image": data.get("header_image"),
        "release_date": data.get("release_date") or {},
        "recommendations": data.get("recommendations") or {},
        "achievements": data.get("achievements") or {},
        # small summary counts to help downstream
        "screenshots_count": len(data.get("screenshots") or []),
        "movies_count": len(data.get("movies") or []),
        "timestamp": datetime.utcnow().isoformat(),
    }
    # optionally include raw data for some nested fields if needed (commented out)
    # rec["raw_appdetail"] = data
    return rec

# ---------- Orchestration ----------
def process_toplist_and_send(params_list, page_list):
    for update_param in params_list:
        for page_no in page_list:
            params = PARAMS_SR_DEFAULT.copy()
            params.update(update_param)
            params["page"] = page_no

            sr = get_search_results(params)
            items = sr.get("items", []) if sr else []
            print_log(f"Fetched {len(items)} search items page={page_no} filter={update_param.get('filter')}")

            for item in items:
                # extract appid from logo (best-effort)
                try:
                    item["appid"] = re.search(r"steam/\w+/(\d+)", item.get("logo", "")).group(1)
                except Exception:
                    item["appid"] = None

                appid = item.get("appid")
                if not appid:
                    print_log("Skipping item without appid:", item.get("name"))
                    continue

                appdetails = get_app_details(appid)
                item["appdetail"] = appdetails

                # prepare and send game_info message
                info_rec = flatten_appdetail_record(item)
                kafka_send(TOPIC_GAME_INFO, info_rec, key=str(info_rec.get("appid")))

                # fetch reviews and send comments
                for review in fetch_steam_reviews(appid, max_pages=3, delay=1):
                    kafka_send(TOPIC_GAME_COMMENTS, review, key=str(appid))

                # small pause between games to avoid aggressive scraping
                time.sleep(1)

    # ensure all messages delivered
    producer.flush()
    print_log("Finished sending all game info and comments.")

# ---------- Main ----------
if __name__ == "__main__":
    # Example usage: process 1 page of topsellers and push to Kafka
    PARAMS_LIST = [
        {"filter": "topsellers"},
        # add more filters if desired:
        # {"filter": "globaltopsellers"}, {"filter": "popularnew"},
    ]
    PAGE_LIST = [1]  # increase to fetch more pages

    print_log("Starting Steam -> Kafka pipeline")
    try:
        process_toplist_and_send(PARAMS_LIST, PAGE_LIST)
    except KeyboardInterrupt:
        print_log("Interrupted by user.")
    finally:
        producer.flush()
        print_log("Producer flushed. Exiting.")
