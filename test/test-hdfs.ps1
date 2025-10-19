# test-hdfs.ps1
$ErrorActionPreference = "Stop"

# Deploy dependencies
kubectl apply -f zookeeper.yaml
kubectl rollout status --watch --timeout=5m statefulset/simple-zk-server-default

kubectl apply -f hdfs-znode.yaml
kubectl apply -f hdfs.yaml
kubectl rollout status --watch --timeout=10m statefulset/simple-hdfs-datanode-default
kubectl rollout status --watch --timeout=10m statefulset/simple-hdfs-namenode-default
kubectl rollout status --watch --timeout=10m statefulset/simple-hdfs-journalnode-default

kubectl apply -f webhdfs.yaml
kubectl rollout status statefulset/webhdfs --timeout=5m

# Create test file
"some hdfs test data" | Out-File -Encoding ascii testdata.txt

# Copy to pod
kubectl cp ./testdata.txt webhdfs-0:/tmp

# Step 1: initiate file creation
$resp = kubectl exec webhdfs-0 -- curl -s -XPUT -T /tmp/testdata.txt "http://simple-hdfs-namenode-default-0.simple-hdfs-namenode-default.default.svc.cluster.local:9870/webhdfs/v1/testdata.txt?user.name=stackable&op=CREATE&noredirect=true"
if ($resp -match 'http[^\s"]+') {
    $location = $matches[0]
    Write-Host "Redirected to: $location"
} else {
    Write-Host "Failed to get redirect location."
    exit 1
}

# Step 2: upload to datanode
kubectl exec webhdfs-0 -- curl -s -XPUT -T /tmp/testdata.txt "$location"

# Step 3: verify
kubectl exec webhdfs-0 -- curl -s -XGET "http://simple-hdfs-namenode-default-0.simple-hdfs-namenode-default.default.svc.cluster.local:9870/webhdfs/v1/?op=LISTSTATUS"

# Step 4: cleanup
kubectl exec webhdfs-0 -- curl -s -XDELETE "http://simple-hdfs-namenode-default-0.simple-hdfs-namenode-default.default.svc.cluster.local:9870/webhdfs/v1/testdata.txt?user.name=stackable&op=DELETE"

Remove-Item testdata.txt -ErrorAction SilentlyContinue
Write-Host "WebHDFS test completed successfully."
