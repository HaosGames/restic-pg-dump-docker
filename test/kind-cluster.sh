#!/bin/bash
set -e

# Check if the cluster exists, if not create it
if ! kind get clusters | grep -q "cnpg-dev"; then
    echo "Creating kind cluster..."
    kind create cluster -n cnpg-dev
fi

# Cleanup previous test resources
echo "Cleaning up previous test resources..."
kubectl delete job --ignore-not-found=true --all
kubectl delete cronjob --ignore-not-found=true restic-backup-example
kubectl delete cluster --ignore-not-found=true cluster-example cluster-restored
kubectl delete -f test/persistent-volume-claim.yaml --ignore-not-found=true
kubectl delete -f test/persistent-volume.yaml --ignore-not-found=true
kubectl delete -f test/restic-secret.yaml --ignore-not-found=true
helm uninstall backup --ignore-not-found=true
helm uninstall restore --ignore-not-found=true

# Wait for resources to be deleted
echo "Waiting for resources to be deleted..."
sleep 10

# Apply resources
kubectl apply -f test/restic-secret.yaml
kubectl apply -f test/persistent-volume.yaml
kubectl apply -f test/persistent-volume-claim.yaml

# Install CloudNativePG operator
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.26/releases/cnpg-1.26.1.yaml

# Wait for operator deployment to be ready
echo "Waiting for CloudNativePG operator deployment to be ready..."
kubectl -n cnpg-system wait --for=condition=available deployment --all --timeout=120s

kubectl apply -f test/pg-cluster.yaml

until kubectl wait --for=condition=ready pod -l cnpg.io/cluster=cluster-example,cnpg.io/podRole=instance --timeout=10s; do
	echo "Sleeping for 10 seconds before retry..."
	sleep 10
done

# Create test table and insert data as the app user
echo "Creating test table..."
kubectl exec -it cluster-example-1 -- psql -U app -d app -c "
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

echo "Waiting for the restore job to complete..."
until kubectl wait --for=condition=complete job/restic-restore-example --timeout=300s; do
	echo "Sleeping for 10 seconds before retry..."
	sleep 10
done

echo "Verifying test table in restored cluster..."
kubectl exec -it cluster-restored-1 -- psql -U app -d app -c "\dt test_backup"
kubectl exec -it cluster-restored-1 -- psql -U app -d app -c "SELECT * FROM test_backup;"

echo "Test completed successfully!"
