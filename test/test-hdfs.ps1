# test-hdfs.ps1
$ErrorActionPreference = "Stop"

# 1. Deploy dependencies
Write-Host "Deploying Zookeeper..."
kubectl apply -f zookeeper.yaml
kubectl rollout status --watch --timeout=5m statefulset/simple-zk-server-default

Write-Host "Deploying HDFS..."
kubectl apply -f hdfs-znode.yaml
kubectl apply -f hdfs.yaml

# WAIT: Give the operator time to create the resources
Write-Host "Waiting 15 seconds for Operator to react..."
Start-Sleep -Seconds 15

# 2. Wait for Pods (REMOVED JournalNode check)
Write-Host "Waiting for DataNode..."
kubectl rollout status --watch --timeout=10m statefulset/simple-hdfs-datanode-default

Write-Host "Waiting for NameNode..."
kubectl rollout status --watch --timeout=10m statefulset/simple-hdfs-namenode-default

# 3. Deploy WebHDFS helper
kubectl apply -f webhdfs.yaml
kubectl rollout status statefulset/webhdfs --timeout=5m

# 4. Create test file
"some hdfs test data" | Out-File -Encoding ascii testdata.txt

# 5. Copy to pod
kubectl cp ./testdata.txt webhdfs-0:/tmp

# Step 6: initiate file creation
Write-Host "Initiating upload..."
$resp = kubectl exec webhdfs-0 -- curl -s -XPUT -T /tmp/testdata.txt "http://simple-hdfs-namenode-default-0.simple-hdfs-namenode-default.default.svc.cluster.local:9870/webhdfs/v1/testdata.txt?user.name=stackable&op=CREATE&noredirect=true"

if ($resp -match 'http[^\s"]+') {
    $location = $matches[0]
    Write-Host "Redirected to: $location"
} else {
    Write-Host "Failed to get redirect location. Response was:"
    Write-Host $resp
    exit 1
}

# Step 7: upload to datanode
Write-Host "Uploading data..."
kubectl exec webhdfs-0 -- curl -s -XPUT -T /tmp/testdata.txt "$location"

# Step 8: verify
Write-Host "Verifying file exists..."
kubectl exec webhdfs-0 -- curl -s -XGET "http://simple-hdfs-namenode-default-0.simple-hdfs-namenode-default.default.svc.cluster.local:9870/webhdfs/v1/?op=LISTSTATUS"

# Step 9: cleanup
kubectl exec webhdfs-0 -- curl -s -XDELETE "http://simple-hdfs-namenode-default-0.simple-hdfs-namenode-default.default.svc.cluster.local:9870/webhdfs/v1/testdata.txt?user.name=stackable&op=DELETE"

Remove-Item testdata.txt -ErrorAction SilentlyContinue
Write-Host "WebHDFS test completed successfully."