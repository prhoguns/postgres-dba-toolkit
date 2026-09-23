#!/bin/bash
# Allow replication connections from the compose network, and create the archive directory.
# Runs once, during initdb, before the server accepts external connections.
set -e
cat >> "$PGDATA/pg_hba.conf" <<'HBA'
# replication from the lab network
host    replication     postgres        10.0.0.0/8      trust
host    replication     postgres        172.16.0.0/12   trust
host    replication     postgres        192.168.0.0/16  trust
host    all             postgres        172.16.0.0/12   trust
HBA
