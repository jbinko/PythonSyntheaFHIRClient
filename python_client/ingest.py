import os, uuid,shutil
from azure.storage.blob import BlobServiceClient, BlobClient, ContainerClient, __version__


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
    uploaded_exists = os.path.isfile(output_upload_path) 
    output_error_path = target_path+"/error"
    error_exists = os.path.isfile(output_error_path)
    if not uploaded_exists:
        os.mkdir(output_upload_path)
    if not error_exists:
        os.mkdir(output_error_path)
    for uploaded_file in uploaded_files:
        shutil.move(uploaded_file,output_upload_path)
    for error_file in error_files:
        shutil.move(error_file,output_error_path)
	
def main():
	connection_string = "DefaultEndpointsProtocol=https;AccountName=fhirimporterappsa;AccountKey=Jk9HyUdWiGpTm9jk6VSadWN6xfPQTZrLCFXpbng4mzSGfAXQX8LEMa9yODgyA8QGhlgLOSGrOalZqqxsxCLvcg==;EndpointSuffix=core.windows.net"
	# Create the BlobServiceClient object which will be used to create a container client
	blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        # Create a unique name for the container
	container_name = "fhirimport"
	local_output_path = dir_path = os.path.dirname(os.path.realpath(__file__))
	print(local_output_path)
	local_file_path = "/home/vmadmin/synthea/output/fhir"
	#while(True):
	print("Checking path: "+local_file_path+" for new files...")
	upload_result = list_and_upload_new(blob_service_client,container_name,local_file_path)
	process_uploaded(upload_result,local_output_path)
if __name__ == "__main__":
    main()
