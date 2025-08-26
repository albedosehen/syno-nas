#!/bin/bash

echo 'Starting Doppler comprehensive keyvault management...'
mkdir -p /keyvault/portainer /keyvault/surrealdb /keyvault/shared
chmod -R 755 /keyvault

echo 'Fetching secrets from Doppler...'
doppler run -- /bin/bash -c '
  # Portainer secrets
  printf "%s" "${PORTAINER_ADMIN_PASSWORD}" > /keyvault/portainer/admin_password
  printf "%s" "${PORTAINER_ADMIN_USERNAME:-admin}" > /keyvault/portainer/admin_username
  
  # SurrealDB secrets
  printf "%s" "${SURREALDB_USER:-admin}" > /keyvault/surrealdb/user
  printf "%s" "${SURREALDB_PASS}" > /keyvault/surrealdb/password
  printf "%s" "${SURREALDB_NAMESPACE:-core}" > /keyvault/surrealdb/namespace
  printf "%s" "${SURREALDB_DATABASE:-services}" > /keyvault/surrealdb/database
  
  # Shared secrets for future services
  printf "%s" "${WEBHOOK_URL:-}" > /keyvault/shared/webhook_url
  printf "%s" "${API_BASE_URL:-}" > /keyvault/shared/api_base_url
  printf "%s" "${NOTIFICATION_EMAIL:-}" > /keyvault/shared/notification_email
  
  # Set proper permissions
  chmod -R 644 /keyvault/portainer/* /keyvault/surrealdb/* /keyvault/shared/*
  
  echo "All secrets created successfully:"
  echo "Portainer secrets:"
  ls -la /keyvault/portainer/
  echo "SurrealDB secrets:"
  ls -la /keyvault/surrealdb/
  echo "Shared secrets:"
  ls -la /keyvault/shared/
  
  echo "Username: $(cat /keyvault/portainer/admin_username)"
  echo "Password length: $(wc -c < /keyvault/portainer/admin_password)"
  echo "SurrealDB user: $(cat /keyvault/surrealdb/user)"
  echo "SurrealDB password length: $(wc -c < /keyvault/surrealdb/password)"
'

echo 'Doppler keyvault management active. All services can now access secrets...'
tail -f /dev/null