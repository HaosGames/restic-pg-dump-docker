#!/bin/bash

set -e

for var in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY RESTIC_PASSWORD RESTIC_REPOSITORY; do
	eval [[ -z \${$var+1} ]] && {
		>&2 echo "ERROR: Missing required environment variable: $var"
		exit 1
	}
done

# First try to check if repository exists
if ! restic snapshots &>/dev/null; then
    echo "Repository does not exist, initializing..."
    restic init
else
    echo "Repository exists, checking for locks..."
    restic unlock
fi
