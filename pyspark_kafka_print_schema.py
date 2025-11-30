from pyspark.sql import SparkSession

# ----------------------------------------------------------------------------
# 1. Create Spark Session
# ----------------------------------------------------------------------------
spark = (
    SparkSession.builder
    .appName("KafkaSteamConsumer")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")

# ----------------------------------------------------------------------------
# 2. Kafka connection config
# ----------------------------------------------------------------------------
KAFKA_BOOTSTRAP = "simple-kafka-broker-default-bootstrap.default.svc.cluster.local:9092"
TOPIC = "game_info"     # or "game_comments"

# ----------------------------------------------------------------------------
# 3. Read stream from Kafka (raw Kafka messages)
# ----------------------------------------------------------------------------
df_raw = (
    spark.readStream
    .format("kafka")
    .option("kafka.bootstrap.servers", KAFKA_BOOTSTRAP)
    .option("subscribe", TOPIC)
    .option("startingOffsets", "latest")
    .load()
)

# Convert Kafka bytes → string
df_str = df_raw.selectExpr("CAST(value AS STRING) AS json_str")

# Print schema only (json_str: STRING)
df_str.printSchema()

# ----------------------------------------------------------------------------
# 4. Print messages to console (RAW JSON)
# ----------------------------------------------------------------------------
query = (
    df_str.writeStream
    .format("console")
    .option("truncate", False)
    .option("numRows", 50)
    .start()
)

query.awaitTermination()
