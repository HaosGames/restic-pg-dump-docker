#!/bin/bash

set -e

setup.sh

echo "Dumping database cluster: $PGUSER@$PGHOST:$PGPORT"

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

mkdir -p "/pg_dump"

if [[ "DO_FULL_BACKUP" == "true" ]]; then
	echo "Dumping enitre instance"
	pg_dumpall --clean --if-exists -f /pg_dump/$PGDATABASE.dumpall
else
	echo "Dumping individual database '$PGDATABASE'"
	pg_dump -Fc -f /pg_dump/$PGDATABASE.dump $PGDATABASE
fi

# echo "Dumping global objects for '$PGHOST'"
# pg_dumpall --file="/pg_dump/!globals.sql" --globals-only

echo "Sending database dumps to S3"
while ! restic backup --host "$DB_RESTIC_NAME" "/pg_dump"; do
	echo "Sleeping for 10 seconds before retry..."
	sleep 10
done

echo 'Finished sending database dumps to S3'

rm -rf "/pg_dump"

prune.sh
