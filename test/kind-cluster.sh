#!/bin/bash
set -e

# Delete existing cluster and create new one
kind delete cluster -n cnpg-dev
kind create cluster -n cnpg-dev

# Install CloudNativePG operator
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.26/releases/cnpg-1.26.1.yaml

# Wait for operator to be ready
echo "Waiting for CloudNativePG operator to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cloudnative-pg -n cnpg-system --timeout=120s

# Create initial PostgreSQL cluster
kubectl apply -f test/pg-cluster.yaml
kubectl apply -f test/restic-secret.yaml

# Wait for PostgreSQL cluster to be ready
echo "Waiting for PostgreSQL cluster to be ready..."
kubectl wait --for=condition=ready pod -l cnpg.io/cluster=cluster-example -l cnpg.io/jobRole=initdb --timeout=300s
sleep 10
kubectl wait --for=condition=ready pod -l cnpg.io/cluster=cluster-example -l cnpg.io/podRole=instance --timeout=300s

# Create test table and insert data
echo "Creating test table..."
kubectl exec -it cluster-example-1 -- psql -U postgres -d app -c "
CREATE TABLE test_backup (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO test_backup (name) VALUES ('test1'), ('test2');"

# Install backup chart
helm upgrade --install -f test/helm-values-backup.yaml backup ./charts/backup

# Manually trigger the backup cronjob
echo "Triggering backup cronjob..."
kubectl create job --from=cronjob/restic-backup-example manual-backup

echo "Waiting for backup job to complete..."
kubectl wait --for=condition=complete job -l job-name=manual-backup --timeout=300s

# Verify backup job succeeded
if [[ $(kubectl get jobs -l job-name=manual-backup -o jsonpath='{.items[].status.succeeded}') != "1" ]]; then
    echo "Backup job failed!"
    kubectl logs job/$(kubectl get jobs -l job-name=manual-backup -o jsonpath='{.items[].metadata.name}')
    exit 1
fi

echo "Backup completed successfully!"

# Create a new cluster for restore
kubectl apply -f test/pg-cluster-restore.yaml

# Wait for restored cluster to be ready
echo "Waiting for restored cluster to be ready..."
kubectl wait --for=condition=ready pod -l cnpg.io/cluster=cluster-restored -l cnpg.io/jobRole=initdb --timeout=300s
sleep 10
kubectl wait --for=condition=ready pod -l cnpg.io/cluster=cluster-restored -l cnpg.io/podRole=instance --timeout=300s

# Restore backup
helm upgrade --install -f test/helm-values-restore.yaml backup ./charts/restore
echo "Waiting for backup job to complete..."
kubectl wait --for=condition=complete job -l job-name=restic-restore-example --timeout=300s

# Verify test table exists in restored cluster
echo "Verifying test table in restored cluster..."
kubectl exec -it cluster-restored-1 -- psql -U postgres -d app -c "\dt test_backup"
kubectl exec -it cluster-restored-1 -- psql -U postgres -d app -c "SELECT * FROM test_backup;"

echo "Test completed successfully!"
