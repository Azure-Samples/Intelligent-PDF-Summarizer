targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
@allowed(['australiaeast', 'eastasia', 'eastus', 'eastus2', 'northeurope', 'southcentralus', 'southeastasia', 'swedencentral', 'uksouth', 'westus2', 'eastus2euap'])
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

@allowed([
  'EP1'
  'EP2'
  'EP3'
  'P1v2'
  'P2v2'
  'P3v2'
  'P1v3'
  'P2v3'
  'P3v3'
  'P1mv3'
  'P2mv3'
  'P3mv3'
  'P4mv3'
  'P5mv3'
  'P0v3'
  'S1'
  'B1'
  'B2'
  'B3'
])
param functionSkuName string = 'EP1' // Uses main.parameters.json first

@allowed([
  'ElasticPremium'
  'PremiumV3'
  'Premium0V3'
  'Standard'
  'Basic'
])

param functionSkuTier string = 'ElasticPremium' // Uses main.parameters.json first
param functionReservedPlan bool = true // Set to false to get a Windows OS plan


param documentIntelligenceSkuName string // Set in main.parameters.json
param documentIntelligenceServiceName string = '' // Set in main.parameters.json

param durableFunctionServiceName string = ''
param durableFunctionUserAssignedIdentityName string = ''
param applicationInsightsName string = ''
param appServicePlanName string = ''
param logAnalyticsName string = ''
param resourceGroupName string = ''
param storageAccountName string = ''
param vNetName string = ''
param disableLocalAuth bool = true

param openAiServiceName string = ''

param durableTaskSchedulerName string = ''
param taskHubName string = 'default'

@allowed([
  'northcentralus'
  'australiaeast'
  'centralus'
  'eastasia'
  'eastus2'
  'northeurope'
  'southeastasia'
  'swedencentral'
  'uksouth'
  'westus2'
])
param dtsLocation string = 'northcentralus'
param dtsSkuName string = 'Dedicated'
param dtsCapacity int = 1
 
param openAiSkuName string
@allowed([ 'azure', 'openai', 'azure_custom' ])
param openAiHost string // Set in main.parameters.json

@description('Public network access value for all deployed resources')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

param chatGptModelName string = ''
param chatGptDeploymentName string = ''
param chatGptDeploymentVersion string = ''
param chatGptDeploymentCapacity int = 0

var chatGpt = {
  modelName: !empty(chatGptModelName) ? chatGptModelName : startsWith(openAiHost, 'azure') ? 'gpt-35-turbo' : 'gpt-3.5-turbo'
  deploymentName: !empty(chatGptDeploymentName) ? chatGptDeploymentName : 'chat'
  deploymentVersion: !empty(chatGptDeploymentVersion) ? chatGptDeploymentVersion : '0613'
  deploymentCapacity: chatGptDeploymentCapacity != 0 ? chatGptDeploymentCapacity : 40
}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var functionAppName = !empty(durableFunctionServiceName) ? durableFunctionServiceName : '${abbrs.webSitesFunctions}${resourceToken}'
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'
var dtsResourceName = !empty(durableTaskSchedulerName) ? durableTaskSchedulerName : '${abbrs.durableTaskSchedulers}${resourceToken}'

@description('Id of the user or app to assign application roles')
param principalId string = ''

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module durableFunctionUserAssignedIdentity './core/identity/userAssignedIdentity.bicep' = {
  name: 'DurableFunctionUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    identityName: !empty(durableFunctionUserAssignedIdentityName) ? durableFunctionUserAssignedIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}durable-function-${resourceToken}'
  }
}

// The application backend is a function app
module appServicePlan './core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: functionSkuName // Change this to the desired Elastic Premium SKU
      tier: functionSkuTier
    }
    reserved: functionReservedPlan // Set to false to get a Windows OS plan
  }
}

module durableFunction './app/durable-function.bicep' = {
  name: 'function-app'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    appServicePlanId: appServicePlan.outputs.id
    runtimeName: 'python'
    runtimeVersion: '3.9'
    storageAccountName: storage.outputs.name
    identityId: durableFunctionUserAssignedIdentity.outputs.identityId
    identityClientId: durableFunctionUserAssignedIdentity.outputs.identityClientId
    azureOpenaiChatgptDeployment: chatGptDeploymentName
    azureOpenaiService: openAi.outputs.name
    documentIntelligenceEndpoint: documentIntelligence.outputs.endpoint
    dtsURL: dts.outputs.dts_URL
    taskHubName: dts.outputs.TASKHUB_NAME
    appSettings: {
    }
    virtualNetworkSubnetId: serviceVirtualNetwork.outputs.appSubnetID
  }
}

// Backing storage for Azure functions durable function
module storage './core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
    containers: [{
      name: deploymentStorageContainerName
      publicAccess: 'Blob'
    },{
      name: 'input'
      publicAccess: 'Blob'

    },{
      name: 'output'
      publicAccess: 'Blob'
    }]
    publicNetworkAccess: 'Enabled' // revisit for wave 3
    allowBlobPublicAccess: true
  }
}

var storageRoleDefinitionId  = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' //Storage Blob Data Owner role

// Allow access from durable function to storage account using a user assigned managed identity
module storageRoleAssignmentApiUAMI 'app/storage-Access.bicep' = {
  name: 'storageRoleAssignmentPocessorUAMI'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionID: storageRoleDefinitionId
    principalID: durableFunctionUserAssignedIdentity.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Allow access from durable function to storage account using the Login identity of this bicep (usually AZD CLI)
module storageRoleAssignmentApi 'app/storage-Access.bicep' = {
  name: 'storageRoleAssignmentDurableFunctionLoginIdentity'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionID: storageRoleDefinitionId
    principalID: principalId
    principalType: 'User'
  }
}

// Virtual Network & private endpoint to blob storage
module serviceVirtualNetwork 'app/vnet.bicep' = {
  name: 'serviceVirtualNetwork'
  scope: rg
  params: {
    location: location
    tags: tags
    vNetName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
  }
}

module storagePrivateEndpoint 'app/storage-PrivateEndpoint.bicep' = {
  name: 'servicePrivateEndpoint'
  scope: rg
  params: {
    location: location
    tags: tags
    virtualNetworkName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
    subnetName: serviceVirtualNetwork.outputs.peSubnetName
    resourceName: storage.outputs.name
  }
}

// Monitor application with Azure Monitor
module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    disableLocalAuth: disableLocalAuth  
  }
}

var monitoringRoleDefinitionId = '3913510d-42f4-4e42-8a64-420c390055eb' // Monitoring Metrics Publisher role ID

// Allow access from durable function` to application insights using a managed identity
module appInsightsRoleAssignmentApi './core/monitor/appinsights-access.bicep' = {
  name: 'appInsightsRoleAssignmentDurableFunction'
  scope: rg
  params: {
    appInsightsName: monitoring.outputs.applicationInsightsName
    roleDefinitionID: monitoringRoleDefinitionId
    principalID: durableFunctionUserAssignedIdentity.outputs.identityPrincipalId
  }
}

module openAi './core/ai/cognitiveservices.bicep' = {
  name: 'openai'
  scope: rg
  params: {
    name: !empty(openAiServiceName) ? openAiServiceName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: 'eastus2'
    
    tags: tags
    publicNetworkAccess: 'Enabled'
    sku: {
      name: openAiSkuName
    }
    deployments: [
      {
        name: chatGpt.deploymentName
        capacity: chatGpt.deploymentCapacity
        model: {
          format: 'OpenAI'
          name: chatGpt.modelName
          version: chatGpt.deploymentVersion
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
    ]
  }
}

// Learn more about Azure role-based access control (RBAC) and built-in-roles at https://docs.microsoft.com/en-us/azure/role-based-access-control/overview
var CognitiveServicesRoleDefinitionIds = ['5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'] // Cognitive Services OpenAI User
module openAiRoleUser 'app/openai-Access.bicep' = {
  scope: rg
  name: 'openai-roles'
  params: {
    principalId: durableFunctionUserAssignedIdentity.outputs.identityPrincipalId
    openAiAccountResourceName: openAi.outputs.name
    roleDefinitionIds: CognitiveServicesRoleDefinitionIds
  }
}

module documentIntelligence 'br/public:avm/res/cognitive-services/account:0.5.4' = {
  name: 'documentintelligence'
  scope: rg
  params: {
    name: !empty(documentIntelligenceServiceName)
      ? documentIntelligenceServiceName
      : '${abbrs.cognitiveServicesDocumentIntelligence}${resourceToken}'
    kind: 'FormRecognizer'
    customSubDomainName: !empty(documentIntelligenceServiceName)
      ? documentIntelligenceServiceName
      : '${abbrs.cognitiveServicesDocumentIntelligence}${resourceToken}'
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Allow'
    }
    location: location
    disableLocalAuth: true
    tags: tags
    sku: documentIntelligenceSkuName
  }
}

module documentIntelligenceRoleBackend 'app/documentintelligence-Access.bicep' = {
  scope: rg
  name: 'documentintelligence-role-backend'
  params: {
    principalId: durableFunctionUserAssignedIdentity.outputs.identityPrincipalId
    roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908'
    principalType: 'ServicePrincipal'
  }
}

// Durable Task Scheduler (state store for Durable Functions orchestrations)
module dts './app/dts.bicep' = {
  scope: rg
  name: 'dtsResource'
  params: {
    name: dtsResourceName
    taskhubname: taskHubName
    location: dtsLocation
    tags: tags
    ipAllowlist: [
      '0.0.0.0/0'
    ]
    skuName: dtsSkuName
    skuCapacity: dtsCapacity
  }
}

// Durable Task Data Contributor role ID
var dtsRoleDefinitionId = '0ad04412-c4d5-4796-b79c-f76d14c8d402'

// Allow access from the function app to DTS using user assigned managed identity
module dtsRoleAssignment 'app/dts-Access.bicep' = {
  name: 'dtsRoleAssignment'
  scope: rg
  params: {
    roleDefinitionID: dtsRoleDefinitionId
    principalID: durableFunctionUserAssignedIdentity.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
    dtsName: dts.outputs.dts_NAME
  }
}

// Allow the deployer identity to access the DTS dashboard
module dtsDashboardRoleAssignment 'app/dts-Access.bicep' = if (!empty(principalId)) {
  name: 'dtsDashboardRoleAssignment'
  scope: rg
  params: {
    roleDefinitionID: dtsRoleDefinitionId
    principalID: principalId
    principalType: 'User'
    dtsName: dts.outputs.dts_NAME
  }
}

// App outputs
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.applicationInsightsConnectionString
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output SERVICE_DURABLE_FUNCTION_NAME string = durableFunction.outputs.SERVICE_DURABLE_FUNCTION_NAME
output AZURE_FUNCTION_NAME string = durableFunction.outputs.SERVICE_DURABLE_FUNCTION_NAME
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.name
output AZURE_STORAGE_CONTAINER_NAME string = deploymentStorageContainerName
output DURABLE_TASK_SCHEDULER_NAME string = dts.outputs.dts_NAME
output DURABLE_TASK_SCHEDULER_URL string = dts.outputs.dts_URL
output TASKHUB_NAME string = dts.outputs.TASKHUB_NAME
