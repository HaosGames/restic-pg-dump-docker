#!/bin/bash

set -e

for var in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY RESTIC_PASSWORD RESTIC_REPOSITORY DB_RESTIC_NAME; do
	eval [[ -z \${$var+1} ]] && {
		>&2 echo "ERROR: Missing required environment variable: $var"
		exit 1
	}
done

echo "Checking restic repository status..."
if ! restic snapshots; then
    echo "ERROR: Could not access restic repository or no snapshots found"
    exit 1
fi

echo "Checking for repository locks..."
restic unlock

echo "Available snapshots for host $DB_RESTIC_NAME:"
restic snapshots --host "$DB_RESTIC_NAME" || true
