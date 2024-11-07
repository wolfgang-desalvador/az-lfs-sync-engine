@description('MySQL administrator login name')
@minLength(1)
param mysqlAdminLogin string

@description('MySQL administrator password')
@minLength(8)
@secure()
param mysqlAdminPassword string

@description('Location for all resources.')
param location string

@description('Deploy private DNS Zone')
param deployZone bool

@description('Virtual Network name')
param virtualNetworkName string

@description('Subnet name')
param subnetName string

@description('Virtual Network resource group name')
param virtualNetworkResourceGroupName string

@description('MySQL Server Name')
param mySqlServerName string

var privateEndpointName = '${mySqlServerName}-pe'
var privateDnsZoneName = 'privatelink.mysql.database.azure.com'
var pvtEndpointDnsGroupName = '${privateEndpointName}/mydnsgroupname'


resource mySqlServer 'Microsoft.DBforMySQL/flexibleServers@2024-02-01-preview' = {
  name: mySqlServerName
  location: location
  sku: {
    name: 'Standard_D2ads_v5'
    tier: 'GeneralPurpose'
  }
  properties: {
    administratorLogin: mysqlAdminLogin
    administratorLoginPassword: mysqlAdminPassword
    storage: {
      autoGrow: 'Disabled'
      iops: 1000
      storageSizeGB: 20
    }
    createMode: 'Default'
    version: '8.0.21'
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Disabled'
    }
  }
}


resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-03-01' existing = {
  name: '${virtualNetworkName}/${subnetName}'
  scope: resourceGroup(virtualNetworkResourceGroupName)
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-03-01' existing = {
  name: virtualNetworkName
  scope: resourceGroup(virtualNetworkResourceGroupName)
}


resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: subnet.id
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: mySqlServer.id
          groupIds: [
            'mysqlServer'
          ]
        }
      }
    ]
  }
  dependsOn: [
    subnet
  ]
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deployZone) {
  name: privateDnsZoneName
  location: 'global'
  properties: {}
  dependsOn: [
    vnet
  ]
}

resource privateDnsZoneName_privateDnsZoneName_link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deployZone) {
  parent: privateDnsZone
  name: '${privateDnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource pvtEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = if (deployZone) {
  name: pvtEndpointDnsGroupName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpoint
  ]
}

output serverName string = mySqlServerName
output server string = mySqlServer.id
