from pyspark.sql import SparkSession
import os

def check_topic(spark, topic_name):
    print(f"\n--- Checking Topic: {topic_name} ---")
    try:
        # Read one message from the topic
        # SSL Configuration matches what is found in process_reviews.py
        reader = (spark.read.format("kafka")
            .option("kafka.bootstrap.servers", "simple-kafka-broker-default-bootstrap.default.svc.cluster.local:9093")
            .option("subscribe", topic_name)
            .option("kafka.security.protocol", "SSL")
            .option("kafka.ssl.endpoint.identification.algorithm", "")
            .option("kafka.ssl.truststore.location", "/truststore/truststore.p12")
            .option("kafka.ssl.truststore.type", "PKCS12")
            .option("kafka.ssl.truststore.password", "changeit")
        )
        
        # Determine offsets - getting latest available to ensure we don't block
        # We want to just grab *some* data.
        # batch read requires startingOffsets and endingOffsets or just default to latest if streaming.
        # For batch: "earliest" to "latest" might read too much.
        # Let's try to read with startingOffsets="earliest" and limit 1.
        
        df = reader.option("startingOffsets", "earliest").load()
        
        count = df.count()
        print(f"Total available messages (approx): {count}")
        
        if count > 0:
            row = df.selectExpr("CAST(key AS STRING)", "CAST(value AS STRING)").first()
            print(f"Sample Message (Key): {row.key}")
            print(f"Sample Message (Value): {row.value[:200]}...") # Truncate long values
            return True
        else:
            print("No messages found.")
            return False
            
    except Exception as e:
        print(f"Error reading topic {topic_name}: {e}")
        return False

if __name__ == "__main__":
    spark = SparkSession.builder.appName("KafkaVerification").getOrCreate()
    spark.sparkContext.setLogLevel("ERROR")
    
    topics = ["game_info", "game_player_count", "game_comments"]
    results = {}
    
    for topic in topics:
        results[topic] = check_topic(spark, topic)
        
    print("\n=== Verification Summary ===")
    all_passed = True
    for topic, status in results.items():
        status_str = "PASS" if status else "FAIL"
        print(f"{topic}: {status_str}")
        if not status: all_passed = False
        
    spark.stop()
    if not all_passed:
        exit(1)
