// ----- PARAMETERS

@minLength(3)
@maxLength(7)
@description('Prefix for a project resources.')
param projectPrefix string

@minLength(6)
@description('Specifies the Administrator login for SQL Server.')
param sqlServerLogin string

@minLength(12)
@secure()
@description('Specifies the Administrator password for SQL Server.')
param sqlServerPassword string

@minLength(6)
@description('Specifies the Administrator login name for VM.')
param localAdminUserName string

@minLength(12)
@secure()
@description('Specifies the Administrator password for VM.')
param localAdminPassword string

// Optional Parameter
@description('Target region/location for deployment of resources.')
param location string = resourceGroup().location

// Optional Parameter
@description('Tags to be associated with deployed resources.')
param resourceTags object = (contains(resourceGroup(), 'tags') ? resourceGroup().tags : {} )

// Optional Parameter
@description('Address space of the Virtual Network.')
param vNetPrefix string = '10.0.0.0/16'

// Optional Parameter
@description('Address space of the Compute Plane subnet.')
param subnetComputePlanePrefix string = '10.0.0.0/20'

// Optional Parameter
@description('Address space of the Private Link subnet.')
param subnetPrivateLinkPrefix string = '10.0.32.0/23'

// Optional Parameter
@description('Number of days for which to retain logs.')
param logRetentionInDays int = 45

// ----- VARIABLES

var enable_private_endpoints = false

var lowerProjectPrefix = toLower(projectPrefix)

var plDfsDnsZone = 'privatelink.dfs.${environment().suffixes.storage}'
var plSnpsSqlDnsZone = 'privatelink.sql.azuresynapse.net'

var vNetName = '${lowerProjectPrefix}-synthea-vnet'

var laUniqueName = '${lowerProjectPrefix}-synthea-la'
var appInsightsUniqueName = '${lowerProjectPrefix}-synthea-appins'
var appSvcPlanUniqueName = '${lowerProjectPrefix}-synthea-appplan'
var appSvcFunctionUniqueName = '${lowerProjectPrefix}-synthea-appfce01'

var synapseUniqueName = '${lowerProjectPrefix}synthea'

var saLakeUniqueName = '${lowerProjectPrefix}synthealakesa'
var saLakeContainerName = 'workspace'

var vmName = '${lowerProjectPrefix}syntheavm'
var vmSize = 'Standard_D2_v3'
var vmPIPName = '${lowerProjectPrefix}syntheavmpip'

var healthcareWksUniqueName = '${lowerProjectPrefix}syntheahcapi'
var fhirName = '${lowerProjectPrefix}fhir'
var fhirservicename = '${healthcareWksUniqueName}/${fhirName}'
var loginURL = environment().authentication.loginEndpoint
var authority = '${loginURL}${tenant().tenantId}'
var audience = 'https://${healthcareWksUniqueName}-${fhirName}.fhir.azurehealthcareapis.com'

// ----- PRIVATE LINK

resource plDFSZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: plDfsDnsZone
  location: 'global'
  tags: resourceTags
  properties: {}
}

resource plDFSZoneVNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${plDFSZone.name}/${plDFSZone.name}'
  location: 'global'
  tags: resourceTags
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource plSNPSZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enable_private_endpoints) {
  name: plSnpsSqlDnsZone
  location: 'global'
  tags: resourceTags
  properties: {}
}

resource plSNPSZoneVNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enable_private_endpoints) {
  name: '${plSNPSZone.name}/${plSNPSZone.name}'
  location: 'global'
  tags: resourceTags
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// ----- NETWORKING

resource vnet 'Microsoft.Network/virtualNetworks@2020-07-01' = {
  dependsOn: [
    plDFSZone
  ]
  name: vNetName
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vNetPrefix
      ]
    }
    subnets: [
      {
        name: 'control-plane'
        properties: {
          addressPrefix: subnetComputePlanePrefix
          delegations: [
            {
              name: 'deleg-web-control-plane'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'private-link'
        properties: {
          addressPrefix: subnetPrivateLinkPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
    enableVmProtection: true
    enableDdosProtection: false
  }
}

// ----- STORAGE ACCOUNTS

resource salake 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: saLakeUniqueName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  identity:{
    type: 'SystemAssigned'
  }
  properties: {
    accessTier: 'Hot'
    isHnsEnabled: true
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    // Next lines is needed for web UI access to default storage
    // ---
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    // ---
    encryption:{
      keySource: 'Microsoft.Storage'
      services: {
        file: {
          enabled: true
        }
        blob: {
           enabled: true
        }
      }
    }
  }
}

resource salake_privateLink 'Microsoft.Network/privateEndpoints@2020-08-01' = {
  name: '${saLakeUniqueName}-private-link'
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${saLakeUniqueName}-private-link'
        properties: {
          privateLinkServiceId: salake.id
          groupIds: [
            'dfs'
          ]
        }
      }
    ]
  }
}

resource salake_privateLink_zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-08-01' = {
  name: '${salake_privateLink.name}/private-link'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: salake.name
        properties: {
          privateDnsZoneId: plDFSZone.id
        }
      }
    ]
  }
}

resource salake_blobs 'Microsoft.Storage/storageAccounts/blobServices@2021-08-01' = {
  name: 'default'
  parent: salake
  properties: {
    containerDeleteRetentionPolicy: {
      enabled: false
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: false
    }
    isVersioningEnabled: false
    restorePolicy: {
      enabled: false
    }
  }
}

resource salake_container 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  dependsOn:[
    salake_blobs
  ]
  name: '${salake.name}/default/${saLakeContainerName}'
  properties: {
    //defaultEncryptionScope: 'string'
    //denyEncryptionScopeOverride: bool
    metadata: {}
    publicAccess: 'None'
  }
}

resource salake_blobContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  dependsOn:[
    salake_container
  ]
  name: guid(salake.id, deployment().name)
  scope: salake
  properties: {
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    principalId: synapseWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
    canDelegate: false
    description: 'Read, write, and delete Azure Storage containers and blobs.'
    //condition: 'string'
    //conditionVersion: '2.0'
    //delegatedManagedIdentityResourceId
  }
}

// ----- LOG ANALYTICS

resource la 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: laUniqueName
  location: location
  tags: resourceTags
  //eTag: 'string'
  properties: {
    sku: {
      name: 'PerGB2018'
      //capacityReservationLevel: int
    }
    //features
    //forceCmkForQuery: bool
    retentionInDays: logRetentionInDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    /*workspaceCapping: {
      dailyQuotaGb: any('number')
    }*/
  }
}

// ----- SYNAPSE WORKSPACES

resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: synapseUniqueName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    //azureADOnlyAuthentication: false
    defaultDataLakeStorage: {
      accountUrl: salake.properties.primaryEndpoints.dfs
      filesystem: saLakeContainerName
      //createManagedPrivateEndpoint: true
      //resourceId: salake.id
    }
    //managedResourceGroupName: 'string'
    //publicNetworkAccess: 'Disabled'
    sqlAdministratorLogin: sqlServerLogin
    sqlAdministratorLoginPassword: sqlServerPassword
    //trustedServiceBypassEnabled: false
    //virtualNetworkProfile: {
    //  computeSubnetId: vnet.properties.subnets[0].id
    //}
  }
}

resource synapseWorkspace_sql_privateLink 'Microsoft.Network/privateEndpoints@2020-08-01' = if (enable_private_endpoints) {
  name: '${synapseUniqueName}-sql-private-link'
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${synapseUniqueName}-sql-private-link'
        properties: {
          privateLinkServiceId: synapseWorkspace.id
          groupIds: [
            'sql'
          ]
        }
      }
    ]
  }
}

resource synapseWorkspace_sql_privateLink_zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-08-01' = if (enable_private_endpoints) {
  name: '${synapseWorkspace_sql_privateLink.name}/private-link'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: synapseWorkspace.name
        properties: {
          privateDnsZoneId: plSNPSZone.id
        }
      }
    ]
  }
}

resource synapseWorkspace_srvlessSql_privateLink 'Microsoft.Network/privateEndpoints@2020-08-01' = if (enable_private_endpoints) {
  name: '${synapseUniqueName}-srvlessSql-private-link'
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${synapseUniqueName}-srvlessSql-private-link'
        properties: {
          privateLinkServiceId: synapseWorkspace.id
          groupIds: [
            'sqlondemand'
          ]
        }
      }
    ]
  }
}

resource synapseWorkspace_srvlessSql_privateLink_zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-08-01' = if (enable_private_endpoints) {
  name: '${synapseWorkspace_srvlessSql_privateLink.name}/private-link'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: synapseWorkspace.name
        properties: {
          privateDnsZoneId: plSNPSZone.id
        }
      }
    ]
  }
}

resource synapseWorkspace_dev_privateLink 'Microsoft.Network/privateEndpoints@2020-08-01' = if (enable_private_endpoints) {
  name: '${synapseUniqueName}-dev-private-link'
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${synapseUniqueName}-dev-private-link'
        properties: {
          privateLinkServiceId: synapseWorkspace.id
          groupIds: [
            'dev'
          ]
        }
      }
    ]
  }
}

resource synapseWorkspace__dev_privateLink_zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-08-01' = if (enable_private_endpoints) {
  name: '${synapseWorkspace_dev_privateLink.name}/private-link'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: synapseWorkspace.name
        properties: {
          privateDnsZoneId: plSNPSZone.id
        }
      }
    ]
  }
}

resource synapseWorkspace_FirewallAllowAllWindowsAzureIps 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = if (!enable_private_endpoints) {
  name: 'AllowAllWindowsAzureIps'
  parent: synapseWorkspace
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

resource synapseWorkspace_FirewallAllowAll 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = if (!enable_private_endpoints) {
  name: 'AllowAll'
  parent: synapseWorkspace
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

// ----- HEALTHCARE WORKSPACES

resource healthcareWorkspace 'Microsoft.HealthcareApis/workspaces@2021-06-01-preview' = {
  name: healthcareWksUniqueName
  location: location
  tags: resourceTags
}

resource healthcareWorkspace_FHIR 'Microsoft.HealthcareApis/workspaces/fhirservices@2021-06-01-preview' = {
  dependsOn: [
    healthcareWorkspace
  ]
  name: fhirservicename
  location: location
  tags: resourceTags
  kind: 'fhir-R4'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    accessPolicies: []
    authenticationConfiguration: {
      authority: authority
      audience: audience
      smartProxyEnabled: true
    }
  }
}

// ----- APP INSIGHTS

resource appSvc_insights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsUniqueName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    DisableIpMasking: false
    // DisableLocalAuth: false
    //ImmediatePurgeDataOn30Days: false
    Flow_Type: 'Bluefield'
    //ForceCustomerStorageForProfiler: bool
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    Request_Source: 'rest'
    RetentionInDays: 30
    //SamplingPercentage: int
    WorkspaceResourceId: la.id
  }
}

// ----- APP SERVICES

resource appSvcPlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: appSvcPlanUniqueName
  location: location
  tags: resourceTags
  sku: {
    name: 'S1'
  }
  kind: 'App'
}

resource appSvc_functionApp 'Microsoft.Web/sites@2021-01-01' = {
  name: appSvcFunctionUniqueName
  kind: 'functionapp'
  location: location
  tags: resourceTags
  properties: {
    enabled: true
    serverFarmId: appSvcPlanUniqueName
    siteConfig: {
      requestTracingEnabled: true
      remoteDebuggingEnabled: false
      httpLoggingEnabled: true
      //logsDirectorySizeLimit: int
      detailedErrorLoggingEnabled: true
      //publishingUsername: 'string'
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: reference(appSvc_insights.id, '2014-04-01').InstrumentationKey
        }
      ]
      //azureStorageAccounts: {}
      connectionStrings: [
      ]
      alwaysOn: true
      //tracingOptions: 'string'
      http20Enabled: true
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      preWarmedInstanceCount: 1
    }
    httpsOnly: true
    storageAccountRequired: false
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource appSvc_functionAppNet 'Microsoft.Web/sites/networkConfig@2021-01-01' = {
  dependsOn:[
    appSvc_functionApp
  ]
  name: '${appSvcFunctionUniqueName}/VirtualNetwork'
  properties:{
    swiftSupported:true
    subnetResourceId: vnet.properties.subnets[0].id
  }
}

// ----- VIRTUAL MACHINES

resource vm_nic 'Microsoft.Network/networkInterfaces@2021-03-01' = {
  name: '${vmName}-NIC'
  location: location
  tags: resourceTags
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: 'IPCfg1'
        properties: {
          primary: true
          privateIPAddressVersion: 'IPv4'
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[1].id
          }
          publicIPAddress: {
            id: vm_pip.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: vmName
  location: location
  tags: resourceTags
  properties: {
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    hardwareProfile: {
      vmSize: vmSize
    }
    networkProfile: {
      networkInterfaces:[
        {
          id: vm_nic.id
          properties:{
            primary:true
            deleteOption:'Delete'
          }
        }
      ]
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts' // Get-AzVMImage -Location "eastus" -PublisherName "Canonical" -Offer "UbuntuServer"
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}-OSDISK'
        osType: 'Linux'
        createOption: 'FromImage'
        deleteOption:'Delete'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: localAdminUserName
      adminPassword: localAdminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
        provisionVMAgent: true
      }
    }
  }
}

resource vm_pip 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: vmPIPName
  location: location
  tags: resourceTags
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: toLower('${vmName}-${uniqueString(resourceGroup().id, vmName)}')
    }
  }
}

resource vm_script 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  name: 'Script'
  location: location
  parent: vm
  tags: resourceTags
  properties: {
    type: 'CustomScript'
    publisher: 'Microsoft.Azure.Extensions'
    typeHandlerVersion: '2.1'
    settings:{
    }
    protectedSettings:{
      commandToExecute: 'bash deploy.sh "DefaultEndpointsProtocol=https;AccountName=${salake.name};AccountKey=${listKeys(salake.id, salake.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}" 120 "./fhir_out" "./out" "./log" "workspace"'
      fileUris: [
        'https://raw.githubusercontent.com/jbinko/PythonSyntheaFHIRClient/main/python_client/deploy.sh'
      ]
    }
    autoUpgradeMinorVersion: true
    //enableAutomaticUpgrade: true
  }
}
