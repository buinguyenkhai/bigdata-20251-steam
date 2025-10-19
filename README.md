Backend (HDFS + NoSQL)

Overview
This module is in charge of the data storage layer for the project.  
It handles both:
- HDFS — distributed file system for storing large data.
- NoSQL database — for storing structured or semi-structured data.

Responsibilities
- Deploy HDFS pods (NameNode, DataNode).
- Configure Apache Spark to write data into HDFS.
- Set up a NoSQL database (e.g., MongoDB or Cassandra).
- Design a basic schema for storing processed data.

Tools & Technologies
- HDFS (Hadoop 3.x)
- Apache Spark
- MongoDB (NoSQL)
- Docker / Kubernetes (for deployment)
- Python (for Spark write tests)

Expected Output
- Running HDFS service (accessible via web UI or CLI).
- Spark successfully writes sample data to HDFS.
- NoSQL database deployed and tested with sample schema.
- Documentation of setup steps and connection config.


