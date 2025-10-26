from pyspark.sql import SparkSession
import sys
import time # Keep time for the sleep command

# Force stdout/stderr buffers to flush immediately
sys.stdout.flush()
sys.stderr.flush()

# --- Initialize Spark session (THIS IS THE CRASH POINT) ---
spark = (
    SparkSession.builder
    .appName("KafkaTestOutput")
    .getOrCreate()
)
spark.sparkContext.setLogLevel("WARN")

print("--- SPARK SESSION STARTED SUCCESSFULLY ---", flush=True) # FIRST TEST LINE

# The rest of the script is removed to simplify and test initialization

# Keep the pod alive for 5 minutes for manual debugging
time.sleep(300) 
print("Test stream finishing...", flush=True)