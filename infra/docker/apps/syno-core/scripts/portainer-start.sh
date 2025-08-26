#!/bin/bash

# Wait for Portainer keyvault secrets to be available
while [ ! -f /keyvault/portainer/admin_password ]; do
  echo "Waiting for Portainer admin password from Doppler keyvault..."
  sleep 2
done

echo "Portainer keyvault secrets available, starting Portainer..."
exec /portainer \
  -H unix:///var/run/docker.sock \
  --admin-password-file /keyvault/portainer/admin_password