// ---- VM Parameters Section ---- //

@description('Virtual machine size specification')
param virtualMachineSize string = 'Standard_D16ds_v5'

@description('Storage account type for VM disk')
param storageAccountType string = 'Premium_LRS'

@description('Image reference')
param imageReference object = {
  publisher: 'almalinux'
  offer: 'almalinux-hpc'
  sku: '8_10-hpc-gen2'
  version: '8.10.2024101801'
}

@description('Virtual machine name')
param virtualMachineName string

@description('Infrastructure location')
param location string = resourceGroup().location

@description('Virtual Network name')
param virtualNetworkName string

@description('Subnet name')
param subnetName string

@description('Virtual Network resource group name')
param virtualNetworkResourceGroupName string


@allowed([
  'password'
  'ssh-key'
])
@description('Authentication type')
param authenticationType string

@secure()
@description('Admin username')
param adminUsername string

@secure()
@description('Admin password or key')
param adminPasswordOrKey string

/// ---- MySQL Flexible Server ---- //

@description('MySQL administrator login name')
@minLength(1)
param mysqlAdminLogin string

@description('MySQL administrator password')
@minLength(8)
@secure()
param mysqlAdminPassword string


@description('Deploy private DNS Zone')
param deployZone bool = true

param utcValue string = utcNow()

// ---- Stroage Account Name ---- //

param storageAccountName string
param storageAccountContainer string


// ----- Lustre configuration ---- //

param metaSyncCLID string = 'cl2'
param robinhoodCLID string = 'cl3'
param lustreMountPoint string = '/lustre-fs'



module mySql 'my_sql_flexible/mysql.bicep' = {
  name: 'mySQLFlexible'
  params: {
    location: location
    mysqlAdminLogin: mysqlAdminLogin
    virtualNetworkName: virtualNetworkName
    subnetName: subnetName
    virtualNetworkResourceGroupName: virtualNetworkResourceGroupName
    mysqlAdminPassword: mysqlAdminPassword
    deployZone: deployZone
  }
}


module virtualMachine 'virtual_machine/vm.bicep' = {
  name: virtualMachineName
  params: {
    virtualMachineName: virtualMachineName
    location: location
    virtualMachineSize: virtualMachineSize
    virtualNetworkName: virtualNetworkName
    subnetName: subnetName
    virtualNetworkResourceGroupName: virtualNetworkResourceGroupName
    imageReference: imageReference
    storageAccountType: storageAccountType
    authenticationType: authenticationType
    adminUsername: adminUsername
    adminPasswordOrKey: adminPasswordOrKey
  }
  dependsOn: [ mySql ]
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource roleAssignmentStorageAccountContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(virtualMachineName, '17d1049b-9a84-46fb-8f53-869881c3d3ab', resourceGroup().id)
  scope: storageAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')
    principalId: virtualMachine.outputs.serviceAssignedIdentityPrincipalId

  }
}

resource roleAssignmentStorageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(virtualMachineName, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe', resourceGroup().id)
  scope: storageAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: virtualMachine.outputs.serviceAssignedIdentityPrincipalId
  }
}


module installMetaSync 'install_lustre_meta_sync/install_lustre_meta_sync.bicep' = {
  name: 'install-metasync-${utcValue}'
  params: {
    changelogId: metaSyncCLID
    lfsMount: lustreMountPoint
    storageAccountName: storageAccountName
    storageContainerName: storageAccountContainer
    virtualMachineName: virtualMachineName
    deploymentName: 'install-metasync-${utcValue}'
    location: location
  }
  dependsOn: [ virtualMachine ]
}



module installRobinhood 'install_robinhood/install_robinhood.bicep' = {
  name: 'install-robinhood-${utcValue}'
  params: {
    changelogId: robinhoodCLID
    lfsMount: lustreMountPoint
    storageAccountName: storageAccountName
    storageContainerName: storageAccountContainer
    virtualMachineName: virtualMachineName
    deploymentName: 'install-robinhood-${utcValue}'
    location: location
    mysqlAdminLogin: mysqlAdminLogin
    mysqlAdminPassword: mysqlAdminPassword
    mysqlServer: '${mySql.outputs.serverName}.mysql.database.azure.com'
  }
  dependsOn: [ virtualMachine ]
}
