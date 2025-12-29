from pyspark.sql import SparkSession
from pyspark.sql.types import *
from pyspark.sql.functions import col
import os

# --- Ensure Correct Python Executable for PySpark ---
os.environ['PYSPARK_PYTHON'] = 'E:/Anaconda/python.exe'

MONGO_URI = "mongodb://127.0.0.1:27017"
MONGO_PACKAGE = "org.mongodb.spark:mongo-spark-connector_2.13:10.3.0"

DB_NAME = "bigdata"
COLLECTION_NAME = "results"

# ------------------------------------------------------------
# 0. START SPARK
# ------------------------------------------------------------
spark = (
    SparkSession.builder
        .appName("MongoUpdateDemo")
        .config("spark.jars.packages", MONGO_PACKAGE)
        .config("spark.mongodb.write.connection.uri", MONGO_URI)
        .config("spark.mongodb.read.connection.uri", MONGO_URI)
        .getOrCreate()
)

print("\nSpark Started.")


# ------------------------------------------------------------
# 1. INSERT INITIAL DATA (ONLY IF COLLECTION IS EMPTY)
# ------------------------------------------------------------
df_existing = (
    spark.read.format("mongodb")
        .option("database", DB_NAME)
        .option("collection", COLLECTION_NAME)
        .load()
)

if df_existing.count() == 0:
    print("\nCollection empty → inserting initial rows.")

    initial_data = [
        (1, "Lucas", "Big Data"),
        (2, "Nguyen", "HDFS Integration")
    ]

    schema = StructType([
        StructField("id", IntegerType(), True),
        StructField("name", StringType(), True),
        StructField("topic", StringType(), True)
    ])

    df_initial = spark.createDataFrame(initial_data, schema)

    df_initial.write.format("mongodb") \
        .mode("append") \
        .option("database", DB_NAME) \
        .option("collection", COLLECTION_NAME) \
        .save()

else:
    print("\nInitial rows already exist. Skipping insertion.")


# ------------------------------------------------------------
# 2. READ BACK TO GET Lucas's MongoDB _id
# ------------------------------------------------------------
df_read = (
    spark.read.format("mongodb")
        .option("database", DB_NAME)
        .option("collection", COLLECTION_NAME)
        .load()
)

lucas_row = df_read.filter(col("id") == 1).select("_id").first()
lucas_oid = str(lucas_row["_id"])

print(f"\nLucas Mongo _id = {lucas_oid}")


# ------------------------------------------------------------
# 3. BUILD UPDATE + INSERT DATAFRAME
# ------------------------------------------------------------
update_data = [
    (lucas_oid, 1, "Lucas", "Advanced Spark"),      # update
    (None,      3, "Chen",  "Kafka Streaming")      # insert new
]

update_schema = StructType([
    StructField("_id", StringType(), True),
    StructField("id", IntegerType(), True),
    StructField("name", StringType(), True),
    StructField("topic", StringType(), True)
])

df_update = spark.createDataFrame(update_data, update_schema)

print("\nData to Upsert:")
df_update.show(truncate=False)


# ------------------------------------------------------------
# 4. UPSERT DOCUMENTS
# ------------------------------------------------------------
df_update.write.format("mongodb") \
    .mode("append") \
    .option("database", DB_NAME) \
    .option("collection", COLLECTION_NAME) \
    .option("replaceDocument", "true") \
    .save()

print("\nUpsert complete.")


# ------------------------------------------------------------
# 5. VERIFY FINAL RESULT
# ------------------------------------------------------------
df_final = (
    spark.read.format("mongodb")
        .option("database", DB_NAME)
        .option("collection", COLLECTION_NAME)
        .load()
)

print("\nFinal MongoDB Content:")
df_final.show(truncate=False)

spark.stop()
