# Azure IP Ranges Script

This script is a utility for retrieving and formatting the IP ranges of Microsoft Azure services. 

# Last update
This repository contains the IPs from "ServiceTags_Public_20230508.json"

## Description

The script begins by downloading a JSON file from Microsoft's download page that contains the latest IP ranges for all Azure services. It then parses the JSON file to 
extract the unique system services and their associated IP addresses.

The IP addresses for each service are written to separate text files named after the service. These files are stored in the `ranges-services-pa` directory within the 
`output` directory. The format of these files is compatible with Palo Alto Networks (PA) devices.
