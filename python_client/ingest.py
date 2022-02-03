import sys
import os
import uuid
import shutil
import time
import json
from azure.storage.blob import BlobServiceClient, BlobClient, ContainerClient, __version__

class Config:
	def __init__(self,filename):
		self.required_config_keys = ["polling_interval","output_path","connection_string","container_name"]
		config_file = open(filename,"r")
		self.config_map = json.load(config_file)
		config_file.close()
	def check_config(self):
		configOK = True
		keys = self.config_map.keys()
		for required_key in self.required_config_keys:
			if not required_key in keys:
				print("Missing configuration setting: "+required_key)
				configOK = False
		return configOK
	def get_config_map(self):
		return self.config_map
def list_and_upload_new(blob_service_client,container_name, local_path):
	files = os.listdir(local_path)
	results = {}
	results["uploaded"] = []
	results["error"] = []
	# Create the container
	for current_file in files:
		if ".json" in current_file:
			file_with_path = local_path+"/"+current_file
			try:
				file_to_upload = open(file_with_path).read()
				blob_client = blob_service_client.get_blob_client(container=container_name,blob=current_file)
				print("Uploading "+current_file+" to blob account...")
				blob_client.upload_blob(file_to_upload)
				results["uploaded"].append(file_with_path)
			except Exception as ex:
				print('Exception:')
				print(ex)
				results["error"].append(file_with_path)
	return results
def process_uploaded(upload_result,target_path):
	uploaded_files = upload_result["uploaded"]
	error_files = upload_result["error"]
	output_upload_path = target_path+"/uploaded"
	uploaded_exists = os.path.exists(output_upload_path) 
	output_error_path = target_path+"/error"
	error_exists = os.path.exists(output_error_path)
	if not uploaded_exists:
		os.mkdir(output_upload_path)
	if not error_exists:
		os.mkdir(output_error_path)
	for uploaded_file in uploaded_files:
		shutil.move(uploaded_file,output_upload_path)
	for error_file in error_files:
		shutil.move(error_file,output_error_path)
	
def main():
	if len(sys.argv) < 2:
		print("No configuration file given.")
		exit(-1)
	filename = sys.argv[1]
	config = Config(filename)
	if not config.check_config():
		print("Bad configuration file: "+ filename)
		exit(-1)
	config_map = config.get_config_map()
	connection_string = config_map["connection_string"] 
	container_name = config_map["container_name"]
	polling_interval = int(config_map["polling_interval"])
	local_file_path = config_map["output_path"]
	#local_file_path = "/home/vmadmin/synthea/output/fhir"
	#"fhirimport"
	#"DefaultEndpointsProtocol=https;AccountName=fhirimporterappsa;AccountKey=Jk9HyUdWiGpTm9jk6VSadWN6xfPQTZrLCFXpbng4mzSGfAXQX8LEMa9yODgyA8QGhlgLOSGrOalZqqxsxCLvcg==;EndpointSuffix=core.windows.net"
	# Create the BlobServiceClient object which will be used to create a container client
	blob_service_client = BlobServiceClient.from_connection_string(connection_string)
	# Create a unique name for the container
	local_output_path = dir_path = os.path.dirname(os.path.realpath(__file__))
	print(local_output_path)
	while(True):
		print("Checking path: "+local_file_path+" for new files...")
		upload_result = list_and_upload_new(blob_service_client,container_name,local_file_path)
		process_uploaded(upload_result,local_output_path)
		time.sleep(polling_interval)
if __name__ == "__main__":
	main()
