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
