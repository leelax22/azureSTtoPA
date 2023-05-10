#!/bin/bash

# Load environment variables
source .env

# Add path of binary during script execution
export PATH=$PATH:$DIR_SCRIPT

# Define the URL of the page
url="https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519"

# Create folders for IP addresses based on system services and properties if they don't exist
mkdir -p ranges-services-pa ranges-name-pa

# Download the HTML of the page
page_html=$(curl -s "$url")

# Extract the URL of the JSON file
json_url=$(echo "$page_html" | grep -Po 'https://download.microsoft.com/download/[^"]*.json' | head -n 1)

# Get the original filename from the URL
json_filename=$(basename "$json_url")

# Check if the downloaded file already exists
if [ -e "$json_filename" ]; then
  echo "File $json_filename already exists. Exiting."
  exit 1
fi

# Download the JSON file and save it to the current directory with its original name
curl -o "$json_filename" "$json_url"

# Check if the downloaded file is a properly constructed JSON file
if ! jq empty "$json_filename" > /dev/null 2>&1; then
  echo "Downloaded file is not a valid JSON. Exiting."
  exit 1
fi

# Make a copy of the file as ServiceTags_Public.json for processing
cp "$json_filename" ServiceTags_Public.json

# Get unique system services and convert it to an array
services=($(jq -r '.values[].properties.systemService' ServiceTags_Public.json | sort -u))

# Get unique properties and convert it to an array
properties=($(jq -r '.values[].properties | keys[]' ServiceTags_Public.json | sort -u))

# Process each system service in parallel
for service in "${services[@]}"; do
  # If the service name is not empty, write the IP addresses to a new file named after the service in the output folder
  if [ -n "$service" ]; then
    # Clear the service file
    > "ranges-services-pa/${service}.txt"

    # Get all the addresses for this service
    addresses=$(jq -r --arg service "$service" '.values[] | select(.properties.systemService == $service) | .properties.addressPrefixes[]?' ServiceTags_Public.json)

    # Loop through each address and write it to the appropriate file
    for address in $addresses; do
      echo "$address" >> "ranges-services-pa/${service}.txt"
    done &
  fi
done

# Process each property in parallel
for property in "${properties[@]}"; do
  # If the property name is not empty, write the IP addresses to a new file named after the property in the output folder
  if [ -n "$property" ]; then
    # Clear the property file
    > "ranges-name-pa/${property}.txt"

    # Get all the addresses for this property
    addresses=$(jq -r --arg property "$property" '.values[] | select(has("properties") | not) | .properties[$property][]?' ServiceTags_Public.json)

    # Loop through each address and write it to the appropriate file
    for address in $addresses; do
      echo "$address" >> "ranges-name-pa/${property}.txt"
    done &
  fi
done

# Wait for all background processes to finish
wait

# Update the readme.md file with the source file information
sed -i "/^# Last update.*/a This repository contains the IPs from \"$json_filename\"" readme.md

# Initialize the Git repository if it doesn't exist
if [ ! -d ".git" ]; then
  git init
fi

# Create and checkout the main branch
git checkout -b main

# Add all files to the Git repository
git add .

# Commit the changes
git commit -m "Automated update"

# Set the remote URL to your GitHub repository
git remote set-url origin https://$GITHUB_USERNAME:$GITHUB_TOKEN@github.com/$GITHUB_USERNAME/$REPO_NAME

# Push the changes to the GitHub repository
git push -u origin main -f
