#!/bin/bash
# Build the replica from a base backup of the primary, then start it in standby mode.
# Idempotent: if the data directory is already a standby, just start it.
set -euo pipefail
DATA=/var/lib/postgresql/data

if [ ! -s "$DATA/PG_VERSION" ]; then
  echo "[replica] taking base backup from primary"
  rm -rf "${DATA:?}"/*
  until pg_isready -h primary -U postgres -q; do sleep 1; done
  # -R writes standby.signal and primary_conninfo; -X stream keeps WAL consistent during the copy
  pg_basebackup -h primary -U postgres -D "$DATA" -Fp -Xs -P -R -S replica_slot -C
fi

# The data directory must belong to postgres, and the server refuses to run as root.
chown -R postgres:postgres "$DATA"
chmod 700 "$DATA"
exec gosu postgres postgres \
  -c hot_standby=on \
  -c primary_conninfo='host=primary port=5432 user=postgres password=postgres application_name=replica1'
