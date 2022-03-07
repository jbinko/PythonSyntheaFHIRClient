az group create --name Synthea --location eastus --subscription XXXXXXXXXXXXXXXXXX
az deployment group create --resource-group Synthea --template-file Synthea.bicep --parameters projectPrefix=specifysome sqlServerLogin=specifysome sqlServerPassword=specifysome localAdminUserName='specifysome' localAdminPassword='specifysome' --subscription XXXXXXXXXXXXXXXXXX
