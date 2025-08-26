#!/bin/bash

# Wait for keyvault secrets to be available
while [ ! -f /keyvault/surrealdb/user ] || [ ! -f /keyvault/surrealdb/password ]; do
  echo "Waiting for SurrealDB secrets from Doppler keyvault..."
  sleep 2
done

echo "SurrealDB keyvault secrets available, starting database..."
SURREALDB_USER=$(cat /keyvault/surrealdb/user)
SURREALDB_PASS=$(cat /keyvault/surrealdb/password)
SURREALDB_NS=$(cat /keyvault/surrealdb/namespace)
SURREALDB_DB=$(cat /keyvault/surrealdb/database)

echo "Starting SurrealDB with user: $SURREALDB_USER, namespace: $SURREALDB_NS, database: $SURREALDB_DB"

/surreal start \
  --bind "0.0.0.0:8000" \
  --user "$SURREALDB_USER" \
  --pass "$SURREALDB_PASS" \
  file:/data/database.db