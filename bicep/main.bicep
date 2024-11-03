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



module mySql 'my_sql_flexible/main.bicep' = {
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


module virtualMachine 'virtual_machine/main.bicep' = {
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
