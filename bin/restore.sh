#!/bin/bash

set -e

setup-restore.sh

mkdir -p "/pg_dump"

echo "Checking available snapshots:"
restic snapshots

echo "Receiving latest database backup from S3"
while ! restic restore latest --host "$DB_RESTIC_NAME" --target "/pg_dump" --verbose; do
	echo "Sleeping for 10 seconds before retry..."
	sleep 10
done

echo 'Finished receiving database backups from S3'

echo "Listing contents of /pg_dump:"
ls -la /pg_dump

echo "Restoring database cluster: $PGUSER@$PGHOST:$PGPORT"

# Wait for PostgreSQL to become available.
COUNT=0
until psql -l > /dev/null 2>&1; do
	if [[ "$COUNT" == 0 ]]; then
		echo "Waiting for PostgreSQL to become available..."
	fi
	(( COUNT += 1 ))
	sleep 1
done
if (( COUNT > 0 )); then
	echo "Waited $COUNT seconds."
fi

echo "Restoring database '$PGDATABASE'"
pg_restore \
    --no-owner \
    --role=app \
    --no-privileges \
    --no-acl \
    --verbose \
    -d $PGDATABASE \
    /pg_dump/pg_dump/$PGDATABASE.dump

echo "Restore complete"

rm -rf "/pg_dump"
