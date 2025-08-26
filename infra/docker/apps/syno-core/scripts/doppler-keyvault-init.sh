#!/bin/bash

echo 'Doppler Setup (keyvault)'
mkdir -p /keyvault/portainer /keyvault/surrealdb /keyvault/shared
chmod -R 755 /keyvault

echo 'Fetching secrets from Doppler...'
doppler run -- /bin/bash -c '
  ###########
  # Azurite #
  ###########
  printf "%s" "${AZURITE_ACCOUNT_NAME:-default}" > /keyvault/azurite/account_name
  printf "%s" "${AZURITE_ACCOUNT_KEY:-}" > /keyvault/azurite/account_key


  #############
  # Portainer #
  #############
  printf "%s" "${PORTAINER_ADMIN_PASSWORD:-}" > /keyvault/portainer/admin_password

  #############
  # SurrealDB #
  #############
  printf "%s" "${SURREALDB_USERNAME:-admin}" > /keyvault/surrealdb/username
  printf "%s" "${SURREALDB_PASSWORD:-}" > /keyvault/surrealdb/password
  printf "%s" "${SURREALDB_NAMESPACE:-core}" > /keyvault/surrealdb/namespace
  printf "%s" "${SURREALDB_DATABASE:-services}" > /keyvault/surrealdb/database

  ##########
  # SHARED #
  ##########
  printf "%s" "${WEBHOOK_URL:-}" > /keyvault/shared/webhook_url
  printf "%s" "${API_BASE_URL:-}" > /keyvault/shared/api_base_url
  printf "%s" "${NOTIFICATION_EMAIL:-}" > /keyvault/shared/notification_email

  #################
  # RWWWRSE PROXY #
  #################
  printf "%s" "${RWWWRSE_DOMAINS:-}" > /keyvault/rwwwrse/domains
  printf "%s" "${RWWWRSE_BACKEND:-}" > /keyvault/rwwwrse/backend

  ###############
  # PERMISSIONS # Set permissions on all created keyvault folders
  ###############
  chmod -R 644 /keyvault/azurite/* /keyvault/portainer/* /rwwwrse/* /keyvault/surrealdb/* /keyvault/shared/*
'

echo 'Doppler keyvault management active. All services can now access secrets...'
tail -f /dev/null