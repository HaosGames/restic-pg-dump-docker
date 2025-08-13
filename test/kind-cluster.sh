#!/bin/bash
set -e

# Delete existing cluster and create new one
kind delete cluster -n cnpg-dev
kind create cluster -n cnpg-dev

# Install CloudNativePG operator
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.26/releases/cnpg-1.26.1.yaml

# Wait for operator namespace to be created
echo "Waiting for cnpg-system namespace..."
until kubectl get namespace cnpg-system >/dev/null 2>&1; do
    sleep 2
done

# Wait for operator deployment to be ready
echo "Waiting for CloudNativePG operator deployment to be ready..."
kubectl -n cnpg-system wait --for=condition=available deployment --all --timeout=120s

# Show pod status for debugging
echo "Current pods in cnpg-system namespace:"
kubectl get pods -n cnpg-system

echo "Creating PostgreSQL cluster..."
kubectl apply -f test/pg-cluster.yaml
kubectl apply -f test/restic-secret.yaml
kubectl apply -f test/persistent-volume-claim.yaml

until kubectl wait --for=condition=ready pod -l cnpg.io/cluster=cluster-example,cnpg.io/podRole=instance --timeout=10s; do
	echo "Sleeping for 10 seconds before retry..."
	sleep 10
done

# Create test table and insert data
echo "Creating test table..."
kubectl exec -it cluster-example-1 -- psql -U postgres -d app -c "
CREATE TABLE test_backup (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO test_backup (name) VALUES ('test1'), ('test2');"

helm upgrade --install -f test/helm-values-backup.yaml backup ./charts/backup

# Manually trigger the backup cronjob
echo "Triggering backup cronjob..."
BACKUP_JOB_NAME="manual-backup-$(date +%s)"
kubectl create job --from=cronjob/restic-backup-example "$BACKUP_JOB_NAME"

# Wait for the backup job to complete
echo "Waiting for backup job $BACKUP_JOB_NAME to complete..."
until kubectl wait --for=condition=complete "job/$BACKUP_JOB_NAME" --timeout=300s; do
	echo "Sleeping for 10 seconds before retry..."
	sleep 10
done

# Create a new cluster for restore
kubectl apply -f test/pg-cluster-restore.yaml

until kubectl wait --for=condition=ready pod -l cnpg.io/cluster=cluster-restored,cnpg.io/podRole=instance --timeout=10s; do
	echo "Sleeping for 10 seconds before retry..."
	sleep 10
done

helm upgrade --install -f test/helm-values-restore.yaml restore ./charts/restore

# Verify test table exists in restored cluster
echo "Verifying test table in restored cluster..."
kubectl exec -it cluster-restored-1 -- psql -U postgres -d app -c "\dt test_backup"
kubectl exec -it cluster-restored-1 -- psql -U postgres -d app -c "SELECT * FROM test_backup;"

echo "Test completed successfully!"
