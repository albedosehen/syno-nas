#!/bin/bash

while [ ! -f /keyvault/surrealdb/username ] || [ ! -f /keyvault/surrealdb/password ]; do
  echo "Waiting for SurrealDB secrets from Doppler keyvault..."
  sleep 2
done

echo "SurrealDB keyvault secrets available, starting database..."
SURREALDB_USERNAME=$(cat /keyvault/surrealdb/username)
SURREALDB_PASSWORD=$(cat /keyvault/surrealdb/password)
SURREALDB_NS=$(cat /keyvault/surrealdb/namespace)
SURREALDB_DB=$(cat /keyvault/surrealdb/database)

echo "Starting SurrealDB with user: $SURREALDB_USERNAME, namespace: $SURREALDB_NS, database: $SURREALDB_DB"

/surreal start \
  --bind "0.0.0.0:8000" \
  --user "$SURREALDB_USERNAME" \
  --pass "$SURREALDB_PASSWORD" \
  file:/data/database.db