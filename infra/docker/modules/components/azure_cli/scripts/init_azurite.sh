#!/bin/sh

#========================== AZURITE SETUP ============================
# This script should be executed via the cli container
# Usage:
#   docker-compose exec cli /scripts/az_azurite_container_setup.sh [-f]
# The -f flag forces the setup to run without checking for the setup flag file.

FORCE_SETUP=false
while getopts "f" opt; do
  case $opt in
    f) FORCE_SETUP=true ;;
    *) echo "Usage: $0 [-f]" >&2; exit 1 ;;
  esac
done

# Azurite Service Name default
: "${AZURITE_SERVICE_NAME:=default}"

# AZ Params
AZURITE_ACCOUNT_NAME=$(echo "$AZURITE_ACCOUNTS" | cut -d ':' -f 1)
AZURITE_ACCOUNT_KEY=$(echo "$AZURITE_ACCOUNTS" | cut -d ':' -f 2)
AZURITE_DEFAULT_PROTOCOL="DefaultEndpointsProtocol=http;AccountName=$AZURITE_ACCOUNT_NAME;AccountKey=$AZURITE_ACCOUNT_KEY"
AZURITE_BLOB_ENDPOINT="BlobEndpoint=http://$AZURITE_SERVICE_NAME:10000/$AZURITE_ACCOUNT_NAME"
AZURITE_QUEUE_ENDPOINT="QueueEndpoint=http://$AZURITE_SERVICE_NAME:10001/$AZURITE_ACCOUNT_NAME"
AZURITE_TABLE_ENDPOINT="TableEndpoint=http://$AZURITE_SERVICE_NAME:10002/$AZURITE_ACCOUNT_NAME"
AZURITE_CONNSTRING="$AZURITE_DEFAULT_PROTOCOL;$AZURITE_BLOB_ENDPOINT;$AZURITE_TABLE_ENDPOINT;$AZURITE_QUEUE_ENDPOINT"

PARAMS="--connection-string $AZURITE_CONNSTRING"

SETUP_FLAG_FILE="/data/$AZURITE_SERVICE_NAME.flag"

if [ "$FORCE_SETUP" = false ] && [ -f "$SETUP_FLAG_FILE" ]; then
  echo "Azurite Container $AZURITE_SERVICE_NAME has already been completed. If you want to run the setup again, first delete the $SETUP_FLAG_FILE file in the mounted azurite volume."
else
  echo "Initializing Azurite Container"

  AZURITE_ENDPOINT="http://$AZURITE_SERVICE_NAME:10000"
  until curl -s "$AZURITE_ENDPOINT" > /dev/null; do
    echo "⏳ Waiting for Azurite ($AZURITE_ENDPOINT) to respond.."
    sleep 2
  done
  echo "Azurite connected!"

  blob_roots="sys/ usr/ "
  blob_sys="sys/files sys/tmp"
  blob_usr="usr/home usr/tmp"

  create_blobs() {
    echo "Generating containers.."

    containers="northern-post oneiric"
    for container in $containers; do
      az storage container create --name "$container" $PARAMS

      for root in $blob_roots; do
        az storage blob upload --container-name "$container" --name "$root" -f /dev/null --overwrite $PARAMS

        if [ "$root" = "sys/" ]; then
          for child in $blob_sys; do
            az storage blob upload --container-name "$container" --name "$child" -f /dev/null --overwrite $PARAMS
          done
        elif [ "$root" = "usr/" ]; then
          for child in $blob_usr; do
            az storage blob upload --container-name "$container" --name "$child" -f /dev/null --overwrite $PARAMS
          done
        fi
      done
    done
  }

  create_queues() {
    echo "Generating queues.."
    az storage queue create -n notifications $PARAMS
  }

  create_tables() {
    echo "Creating preference_options table..."
    az storage table create --name "preference_options" $PARAMS >/dev/null
    echo "Done."
  }


insert_options() {
  echo "Seeding preference options..."

  options='[
    {
      "category": "theme",
      "options": [
        {"id": "dark",   "label": "Dark Mode",   "description": "Dark background with light text", "isDefault": "true"},
        {"id": "light",  "label": "Light Mode",  "description": "Light background with dark text", "isDefault": "false"}
      ]
    },
    {
      "category": "language",
      "options": [
        {"id": "en-US", "label": "English (US)", "description": "English, United States", "isDefault": "true"},
        {"id": "es-ES", "label": "Spanish",      "description": "Español",                "isDefault": "false"}
      ]
    },
    {
      "category": "timezone",
      "options": [
        {"id": "America/Anchorage", "label": "Alaska Time", "description": "AKST/AKDT", "isDefault": "true"},
        {"id": "America/Chicago",   "label": "Central Time","description": "CST/CDT",   "isDefault": "false"}
      ]
    }
  ]'

  echo "$options" | jq -c '.[] as $cat | $cat.options[] | {category: $cat.category, id: .id, label: .label, description: .description, isDefault: .isDefault}' \
  | while read -r row; do
      category=$(echo "$row"    | jq -r '.category')
      id=$(echo "$row"          | jq -r '.id')
      label=$(echo "$row"       | jq -r '.label')
      description=$(echo "$row" | jq -r '.description')
      isDefault=$(echo "$row"   | jq -r '.isDefault')

      az storage entity insert \
        --table-name "preference_options" \
        $PARAMS \
        --entity "PartitionKey=$category" \
                "RowKey=$id" \
                "label=$label" \
                "description=$description" \
                "isDefault=$isDefault" >/dev/null

      echo "  inserted: ($category, $id) = $label"
    done

  echo "Done."
}

  create_blobs
  create_queues
  create_tables
  insert_options

  echo "Azurite container setup complete!"
  touch "$SETUP_FLAG_FILE"
fi
