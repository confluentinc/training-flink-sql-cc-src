#!/bin/bash

# Path to the API key file
API_KEY_FILE="/home/training/training-flink-sql-cc/terraform/api-key.txt"

# Read the API key and secret from the file
CONFLUENT_CLOUD_API_KEY=$(grep 'confluent_cloud_api_key' "$API_KEY_FILE" | cut -d '"' -f 2)
CONFLUENT_CLOUD_API_SECRET=$(grep 'confluent_cloud_api_secret' "$API_KEY_FILE" | cut -d '"' -f 2)

# Check if the values were extracted successfully
if [[ -z "$CONFLUENT_CLOUD_API_KEY" || -z "$CONFLUENT_CLOUD_API_SECRET" ]]; then
  echo "Error: Unable to extract API key and secret from $API_KEY_FILE"
  exit 1
fi

# Append the environment variables to the .bashrc file
echo "export CONFLUENT_CLOUD_API_KEY=\"$CONFLUENT_CLOUD_API_KEY\"" >> /home/training/.bashrc
echo "export CONFLUENT_CLOUD_API_SECRET=\"$CONFLUENT_CLOUD_API_SECRET\"" >> /home/training/.bashrc

# Source the .bashrc file to reload the terminal session
source /home/training/.bashrc

echo "Environment variables have been added to /home/training/.bashrc"