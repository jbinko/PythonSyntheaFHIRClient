#! /usr/bin/python3

import sys
import os
import uuid
import shutil
import time
import json
from azure.storage.blob import BlobServiceClient, BlobClient, ContainerClient, __version__

class Config:
	def __init__(self,filename):
		self.required_config_keys = ["polling_interval","FHIR_output_path","connection_string","container_name"]
		config_file = open(filename,"r")
		self.config_map = json.load(config_file)
		config_file.close()
	def check_config(self):
		configOK = True
		keys = self.config_map.keys()
		for required_key in self.required_config_keys:
			if not required_key in keys:
				print("Missing configuration setting: "+required_key,flush=True)
				configOK = False
		return configOK
	def get_config_map(self):
		return self.config_map
class FHIRUploader:
	def __init__(self,connection_string,container_name,polling_interval,FHIR_output_path, local_output_path):
		self.connection_string = connection_string
		self.container_name = container_name
		self.polling_interval = polling_interval
		self.FHIR_output_path = FHIR_output_path
		self.local_output_path = local_output_path
	def init_blob_connection(self): 
		# Create the BlobServiceClient object which will be used to create a container client
		blob_service_client = BlobServiceClient.from_connection_string(self.connection_string)
		return blob_service_client
	def set_blob_connection(self,blob_service_client):
		self.blob_service_client = blob_service_client
	def list_and_upload_new(self):
		files = os.listdir(self.FHIR_output_path)
		results = {}
		results["uploaded"] = []
		results["error"] = []
		# Create the container
		for current_file in files:
			if ".json" in current_file:
				file_with_path = self.FHIR_output_path+"/"+current_file
				try:
					file_to_upload = open(file_with_path,'r').read()
					blob_client = self.blob_service_client.get_blob_client(container=self.container_name,blob=current_file)
					print("Uploading "+current_file+" to blob account...",flush=True)
					blob_client.upload_blob(file_to_upload)
					results["uploaded"].append(file_with_path)
				except Exception as ex:
					print('Exception:')
					print(ex)
					results["error"].append(file_with_path)
		return results
	def run_upload_process(self):
		while(True):
			print("Checking path: "+self.FHIR_output_path+" for new files...",flush=True)
			upload_result = self.list_and_upload_new()
			self.process_uploaded(upload_result,self.local_output_path)
			time.sleep(self.polling_interval)
	def process_uploaded(self,upload_result,target_path):
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
	FHIR_output_path = config_map["FHIR_output_path"]
	local_output_path = os.path.dirname(os.path.realpath(__file__))
	if "local_output_path" in config_map:
		local_output_path = config_map["local_output_path"]
	if "log_path" in config_map:
		log_out = open(config_map["log_path"],"w")
		sys.stdout = log_out	
	print("Config file loaded successfully.\n Polling interval: "+str(polling_interval)+"s\n",flush=True)
	uploader = FHIRUploader(connection_string, container_name, polling_interval, FHIR_output_path,local_output_path)
	blob_service_client = uploader.init_blob_connection()
	uploader.set_blob_connection(blob_service_client)
	uploader.run_upload_process()
if __name__ == "__main__":
	main()
