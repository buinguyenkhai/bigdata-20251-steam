from pyspark.sql import SparkSession
from pyspark.sql.functions import col, upper
import os

# Initialize Spark session
spark = (
    SparkSession.builder
    .appName("KafkaTestIO")
    .config("spark.hadoop.fs.defaultFS", "hdfs://simple-hdfs-namenode-0.simple-hdfs-namenode.default.svc.cluster.local:8020")
    .getOrCreate()
)
spark.sparkContext.setLogLevel("WARN")

print("--- SPARK SESSION STARTED SUCCESSFULLY ---", flush=True)

# Get Kafka details from environment variables
bootstrap_servers = os.environ.get("KAFKA_BOOTSTRAP_SERVERS")
topic = os.environ.get("KAFKA_TOPIC")
hdfs_output_path = "hdfs:///user/stackable/test-output"

print(f"Reading from Kafka topic '{topic}' at {bootstrap_servers}", flush=True)

# Read a stream from Kafka
df = (
    spark.readStream
    .format("kafka")
    .option("kafka.bootstrap.servers", bootstrap_servers)
    .option("subscribe", topic)
    .load()
)

# Perform a simple transformation (convert value to uppercase string)
transformed_df = df.select(upper(col("value").cast("string")).alias("value"))

# Write the transformed stream to HDFS as text files
query = (
    transformed_df.writeStream
    .outputMode("append")
    .format("text")
    .option("path", hdfs_output_path)
    .option("checkpointLocation", f"{hdfs_output_path}/_checkpoint")
    .start()
)

print(f"--- WAITING FOR KAFKA MESSAGES, WRITING TO {hdfs_output_path} ---", flush=True)

query.awaitTermination()