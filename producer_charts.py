import time
import steam_utils as utils

def main():
    utils.print_log("Starting Steam Charts (Game Info) Producer...")
    
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
    
    utils.print_log(f"Processing {len(appids)} apps for Game Info.")

    # 4. Process Loop
    for i, appid in enumerate(appids):
        utils.print_log(f"[{i+1}/{len(appids)}] Processing AppID: {appid}")
        
        # Fetch App Details
        details = utils.get_app_details(appid)
        
        if details.get("success"):
            # Construct a minimal 'item' dict for flattening
            item = {
                "appid": appid, 
                "name": details.get("data", {}).get("name"), 
                "appdetail": details
            }
            
            # Flatten data (handles timestamp_scraped internally)
            # genre_tag is None because we are reading from a mixed ID list, not a genre search
            game_record = utils.flatten_app_data(item, genre_tag=None)
            
            # Send to Kafka
            utils.kafka_send(producer, utils.TOPIC_GAME_INFO, game_record, key=str(appid))
            utils.print_log(f"  > Sent Game Info: {game_record.get('name')}")
        else:
            utils.print_log(f"  > Failed to get details for {appid}, skipping.")

        # Periodic poll to handle callbacks and keep connection alive
        producer.poll(0)
        
        # Rate Limiting (Steam Store API is stricter than UserStats)
        time.sleep(1.5)

    utils.print_log("All AppIDs processed. Flushing producer...")
    producer.flush()
    utils.print_log("Done.")

if __name__ == "__main__":
    main()