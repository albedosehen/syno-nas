#!/bin/bash

echo 'Doppler Setup (keyvault)'
mkdir -p /keyvault/portainer /keyvault/surrealdb /keyvault/shared
chmod -R 755 /keyvault

echo 'Fetching secrets from Doppler...'
doppler run -- /bin/bash -c '
  #############
  # Portainer #
  #############
  printf "%s" "${PORTAINER_ADMIN_PASSWORD}" > /keyvault/portainer/admin_password
  
  #############
  # SurrealDB #
  #############
  printf "%s" "${SURREALDB_USERNAME:-admin}" > /keyvault/surrealdb/username
  printf "%s" "${SURREALDB_PASS}" > /keyvault/surrealdb/password
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
  printf "%s" "${RWWWRSE_DOMAINS:-}" > /keyvault/shared/rwwwrse_domains
  printf "%s" "${RWWWRSE_BACKEND:-}" > /keyvault/shared/rwwwrse_backend

  ###############
  # PERMISSIONS #
  ###############
  chmod -R 644 /keyvault/portainer/* /keyvault/surrealdb/* /keyvault/shared/*
'

echo 'Doppler keyvault management active. All services can now access secrets...'
tail -f /dev/null