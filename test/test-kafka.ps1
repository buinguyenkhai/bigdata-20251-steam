# test-kafka.ps1
$ErrorActionPreference = "Stop"

# Deploy dependencies
kubectl apply -f zookeeper.yaml
kubectl apply -f kafka-znode.yaml
kubectl apply --server-side --force-conflicts -f kafka.yaml

kubectl rollout status --watch --timeout=10m statefulset/simple-kafka-broker-default

# Port-forward Kafka broker in background
$pf = Start-Job { kubectl port-forward svc/simple-kafka-broker-default-bootstrap 9092:9092 > $null 2>&1 }
Start-Sleep -Seconds 3

# Produce data
"some test data" | kubectl run kcat-producer --rm -i --image=edenhill/kcat:1.7.1 --restart=Never -- `
  -b simple-kafka-broker-default-bootstrap:9092 -t test-data-topic -P

# Consume data and save output
kubectl run kcat-consumer --rm -i --image=edenhill/kcat:1.7.1 --restart=Never -- `
  -b simple-kafka-broker-default-bootstrap:9092 -t test-data-topic -C -e | `
  Out-File -Encoding ascii read-data.out

# Verify content
if (Select-String -Path "read-data.out" -Pattern "some test data" -Quiet) {
    Write-Host "Kafka test succeeded!"
} else {
    Write-Host "Kafka test failed!"
}

# Cleanup
Remove-Item read-data.out -ErrorAction SilentlyContinue
Stop-Job $pf | Out-Null
Remove-Job $pf -Force | Out-Null

