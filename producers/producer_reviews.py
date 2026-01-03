import time
import steam_utils as utils

def main():
    utils.print_log("Starting Steam Reviews/Info Producer...")
    
    # 1. Setup Producer
    producer = utils.setup_producer()
    
    # 2. Read AppIDs
    appids = utils.read_processed_appids("processed_appids.txt")
    if not appids:
        utils.print_log("No AppIDs found. Exiting.")
        return

    # 3. Apply Limit
    max_apps = utils.MAX_APPS_TO_PROCESS
    if len(appids) > max_apps:
        utils.print_log(f"Limiting processing to first {max_apps} AppIDs (Total: {len(appids)}).")
        appids = appids[:max_apps]
    
    utils.print_log(f"Processing {len(appids)} apps with {utils.MAX_REVIEW_PAGES} review pages each.")

    # 4. Process Loop
    for i, appid in enumerate(appids):
        utils.print_log(f"[{i+1}/{len(appids)}] Processing AppID: {appid}")
        
        # --- A. Game Info ---
        details = utils.get_app_details(appid)
        if details.get("success"):
            # Construct a minimal 'item' dict for flattening, similar to original logic
            item = {"appid": appid, "name": details.get("data", {}).get("name"), "appdetail": details}
            
            # Note: We don't have "primary_genre" from search context anymore, passing None or we could extract it
            game_record = utils.flatten_app_data(item, genre_tag=None)
            
            utils.kafka_send(producer, utils.TOPIC_GAME_INFO, game_record, key=str(appid))
            utils.print_log(f"  > Sent Game Info: {game_record.get('name')}")
        else:
            utils.print_log(f"  > Failed to get details for {appid}, skipping info.")

        # --- B. Game Reviews ---
        review_count = 0
        for review in utils.fetch_steam_reviews(appid, max_pages=utils.MAX_REVIEW_PAGES):
            utils.kafka_send(producer, utils.TOPIC_GAME_COMMENTS, review, key=str(appid))
            review_count += 1
        
        utils.print_log(f"  > Sent {review_count} reviews.")
        
        # Flush periodically (e.g. every game) to avoid memory buildup
        producer.poll(0)
        
        # Rate Limiting
        time.sleep(1.5)

    utils.print_log("All AppIDs processed. Flushing producer...")
    producer.flush()
    utils.print_log("Done.")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        utils.print_log("Interrupted.")
    except Exception as e:
        utils.print_log(f"Fatal Error: {e}")
