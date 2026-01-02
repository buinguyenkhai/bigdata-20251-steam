import time
from datetime import datetime
import steam_utils as utils

def main():
    utils.print_log("Starting Steam Player Count Producer...")
    
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

    utils.print_log(f"Fetching player counts for {len(appids)} apps.")

    # 4. Process Loop
    for i, appid in enumerate(appids):
        # Fetch Player Count
        p_count = utils.get_current_players(appid)
        
        if p_count >= 0:
            player_record = {
                "appid": int(appid),
                "player_count": p_count,
                "timestamp": datetime.utcnow().isoformat()
            }
            utils.kafka_send(producer, utils.TOPIC_PLAYER_COUNT, player_record, key=str(appid))
            # utils.print_log(f"[{i+1}/{len(appids)}] {appid}: {p_count} players.")
        else:
            utils.print_log(f"[{i+1}/{len(appids)}] {appid}: Failed to get player count.")
        
        # Minimal sleep between calls to be nice to API, but fast enough for cron
        time.sleep(0.5)
        
        # Periodic poll handles callbacks
        if i % 10 == 0:
            producer.poll(0)

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
