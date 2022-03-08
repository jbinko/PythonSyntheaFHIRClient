#/bin/bash
connection_string=$1		
polling_interval=$2		
FHIR_output_path=$3		
local_output_path=$4		
log_path=$5		
container_name=$6		

sudo apt update
sudo apt upgrade -y
sudo apt install python3-pip -y

mkdir /home/synthea
sudo chmod 777 /home/synthea/
cd /home/synthea
git clone https://github.com/jbinko/PythonSyntheaFHIRClient.git
cd ./PythonSyntheaFHIRClient/python_client


echo "Writing config file..."

content=$'{\n\"connection_string\":\"'"${connection_string}"$'\",\n\"polling_interval\":\"'"${polling_interval}"$'\",\n\"FHIR_output_path\":\"'"${FHIR_output_path}"$'\",\n\"local_output_path\":\"'"${local_output_path}"$'\",\n\"log_path\":\"'"${log_path}"$'\",\n\"container_name\":\"'"${container_name}"$'\"\n}' 

echo "$content" > deploy_config.json

sudo mkdir fhir_out
sudo mkdir out
sudo mkdir out/uploaded
sudo pip3 install azure-storage-blob
#sudo ./ingest.py deploy_config.json
