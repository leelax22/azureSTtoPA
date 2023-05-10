# Azure IP Ranges Script

This script is a utility for retrieving and formatting the IP ranges of Microsoft Azure services. 

# Last update
This repository contains the IPs from "ServiceTags_Public_20230508.json"
The output was generated on 10 May 2023 at 07h51 CEST

## Description

The script begins by downloading a JSON file from Microsoft's download page that contains the latest IP ranges for all Azure services. It then parses the JSON file to 
extract the unique system services and their associated IP addresses.

The IP addresses for each service are written to separate text files named after the service. These files are stored in the `ranges-services-pa` directory within the 
`output` directory. The format of these files is compatible with Palo Alto Networks (PA) devices.

## Usage

Run the script using Bash. No parameters are needed.

```bash
./azure_ip_ranges.sh
```

## Output
The output of the script is a series of text files in the output/ranges-services-pa directory. Each file is named after an Azure system service and contains the IP 
ranges for that service.

These files can be used to configure firewall rules on Palo Alto Networks (PA) devices.

## Important
The script uses a personal access token for pushing changes to a GitHub repository. Always ensure your token is kept secret.

## Updates
The script is designed to be run periodically to keep the IP range files up-to-date. Each run of the script downloads the latest JSON file from Microsoft and updates 
the text files accordingly.
