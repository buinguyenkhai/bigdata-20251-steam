#  MongoDB Installation 

## Installation (Windows)

1. Download the MongoDB installer (the latest version):  
   [MongoDB Community Download](https://www.mongodb.com/try/download/community)

2. Run the `.msi` installer and follow setup wizard:
   - Choose **Complete** setup.
   - Enable **Install MongoDB as a Service**.
   - Optionally install **MongoDB Compass (GUI)**.

3. Create data directory (if not installed as service):
   mkdir C:\data\db
   "C:\Program Files\MongoDB\Server\<version>\bin\mongod.exe" --dbpath="C:\data\db"
4. Add mongod.exe path to Environment Variables:
  C:\Program Files\MongoDB\Server\<version>\bin
5. Start MongoDB manually (if needed):
  net start MongoDB
6. Test MongoDB:
  mongosh
## Setup Environment

1. Run the test HDFS on -main directory.
2. Run this line to setup MongoDB in k8s: kubectl apply -f mongodb-deployment.yaml
3. To access MongoDB from cluster: kubectl port-forward svc/mongodb-service 27017:27017
4. Test on new terminal: mongosh mongodb://localhost:27017

