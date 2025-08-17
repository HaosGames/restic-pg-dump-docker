# restic-pg-dump-docker

Docker image that performs PostgreSQL database backups using [restic] for CloudNativePG clusters in Kubernetes. The image provides both backup and restore capabilities, using pg_dump in custom format (-Fc) for efficient backups.

## Features

- Uses S3 as restic repository backend
- Configurable backup schedule via Kubernetes CronJob
- Restore functionality via Kubernetes Job
- Designed for CloudNativePG database clusters
- Uses pg_dump's custom format for efficient backups
- Incremental backups using restic

## Prerequisites

- Kubernetes cluster
- CloudNativePG operator installed
- Helm 3.x
- kubectl
- S3 bucket and credentials

## Installation

The project provides two Helm charts:

### Backup Chart

```bash
helm install backup ./charts/backup -f values.yaml
```

Example values.yaml for backup:
```yaml
backups:
  - name: example
    namespace: default
    dbAppConfig: cluster-example-app  # Secret with database credentials
    resticSecretName: restic-secret  # Secret with restic configuration
    schedule: "0 * * * *"  # Hourly backup
```

### Restore Chart

```bash
helm install restore ./charts/restore -f values.yaml
```

Example values.yaml for restore:
```yaml
restores:
  - name: example
    namespace: default
    dbAppConfig: cluster-restored-app  # Secret with database credentials
    resticSecretName: restic-secret  # Secret with restic configuration
    doCleanup: true # Cleanup db before restore. Defaults to false
    snapshotID: latest # Restore specific snapshotID. Defaults to latest
```

## Required Secrets

### Database Credentials (Created by CloudNativePG)
CloudNativePG automatically creates secrets containing database credentials. These are referenced in the `dbAppConfig` values.

### Restic Configuration
Create a secret with restic and S3 configuration:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: restic-secret
data:
  RESTIC_REPOSITORY: base64-encoded-s3-url  # e.g., s3:s3.amazonaws.com/bucket-name/path
  RESTIC_PASSWORD: base64-encoded-password # used for client-side encryption of the db-dump
  AWS_ACCESS_KEY_ID: base64-encoded-key
  AWS_SECRET_ACCESS_KEY: base64-encoded-secret
```

## Usage

### Creating a Backup

Backups run automatically according to the schedule. To trigger a manual backup:

```bash
kubectl create job --from=cronjob/restic-backup-example manual-backup
```

### Performing a Restore

Deploy the restore chart to restore the latest backup:

```bash
helm install restore ./charts/restore -f values.yaml
```

### Monitoring

Check backup/restore status:

```bash
# For backup jobs
kubectl logs -l job-name=restic-backup-example

# For restore jobs
kubectl logs -l job-name=restic-restore-example
```

## Testing

The project includes a test environment using Kind:

```bash
./test/kind-cluster.sh
```

This script:
1. Creates a Kind cluster
2. Installs CloudNativePG operator
3. Creates test PostgreSQL clusters
4. Sets up a local persistent volume for testing (not needed for production S3 usage)
5. Performs test backup and restore operations

The test environment uses a local persistent volume instead of S3 for easier testing. The volume configuration can be found in the test directory and is not required for production use with S3.

## Important Notes

- Tables should be created as the app user to avoid permission issues with backup/restore
- The S3 bucket should have appropriate permissions for the provided AWS credentials
- Backup and restore operations use the same database user credentials as the application

[restic]: https://restic.net/
