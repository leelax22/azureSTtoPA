#!/bin/bash
# Load environment variables
source .env
# Add path of binary during script execution
export PATH=$PATH:$DIR_SCRIPT

# Define the URL of the page
url="https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519"

# Create output and ranges-services-pa folders if they don't exist
mkdir -p output/ranges-services-pa

# Download the HTML of the page
page_html=$(curl -s "$url")

# Extract the URL of the JSON file
json_url=$(echo "$page_html" | grep -Po 'https://download.microsoft.com/download/[^"]*.json' | head -n 1)

# Get the original filename from the URL
json_filename=$(basename "$json_url")

# Download the JSON file and save it to output folder with its original name
curl -o "output/$json_filename" "$json_url"

# Check if the downloaded file is a properly constructed JSON file
jq empty "output/$json_filename" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Downloaded file is not a valid JSON. Exiting."
  exit 1
fi

# Make a copy of the file as ServiceTags_Public.json for processing
cp "output/$json_filename" output/ServiceTags_Public.json

# Get unique system services and convert it to an array
SYSTEMS=($(jq -r '.values[].properties.systemService' output/ServiceTags_Public.json | sort -u))

# Calculate the total number of services
total_services=${#SYSTEMS[@]}

echo "Total Services: $total_services"

# Initialize progress counter
progress=0

# Loop through each unique system service
for service in "${SYSTEMS[@]}"; do
  # Increment progress counter
  ((progress++))

  echo "Processing Service $progress of $total_services: $service"

  # If the service name is not empty, write the IP addresses to a new file named after the service in the output folder
  if [ -n "$service" ]; then
    # Clear the service file
    > "output/ranges-services-pa/${service}.txt"

    # Get all the addresses for this service
    addresses=$(jq -r --arg service "$service" '.values[] | select(.properties.systemService == $service) | .properties.addressPrefixes[]?' output/ServiceTags_Public.json)

    # Loop through each address
    for address in $addresses; do
      # Print the address to the appropriate file
      echo "$address" >> "output/ranges-services-pa/${service}.txt"
    done
  fi
done

cd output

# Update the readme.md file with the source file information
sed -i "/^# Last update.*/a This repository contains the IPs from \"$json_filename\"" readme.md

# Initialize the Git repository if it doesn't exist
if [ ! -d ".git" ]; then
  git init
fi

# Add all files in the "output" directory to the Git repository
git add .

# Commit the changes
git commit -m "Automated update"

# Set the remote URL to your GitHub repository
# Now we use the GITHUB_USERNAME and GITHUB_TOKEN variables
git remote set-url origin https://$GITHUB_USERNAME:$GITHUB_TOKEN@github.com/$GITHUB_USERNAME/azureIPranges.git

# Push the changes to the GitHub repository
git push -u origin main -f