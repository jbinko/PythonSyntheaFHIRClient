#/bin/bash
connection_string=$1		
polling_interval=$2		
FHIR_output_path=$3		
local_output_path=$4		
log_path=$5		
container_name=$6		

git clone https://github.com/djdean/PythonSyntheaFHIRClient
cd PythonSyntheaFHIRClient

echo "Writing config file..."

content=$'{\n\"connection_string\":\"'"${connection_string}"$'\",\n\"polling_interval\":\"'"${polling_interval}"$'\",\n\"FHIR_output_path\":\"'"${FHIR_output_path}"$'\",\n\"local_output_path\":\"'"${local_output_path}"$'\",\n\"log_path\":\"'"${log_path}"$'\",\n\"container_name\":\"'"${container_name}"$'\"\n}' 

echo "$content" > deploy_config.json
