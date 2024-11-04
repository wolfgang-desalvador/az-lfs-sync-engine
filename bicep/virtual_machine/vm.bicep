@description('Virtual machine size specification')
param virtualMachineSize string

@description('Virtual machine name')
param virtualMachineName string

@description('Infrastructure location')
param location string

@description('Storage account type for VM disk')
param storageAccountType string

@description('Virtual Network name')
param virtualNetworkName string

@description('Subnet name')
param subnetName string

@description('Virtual Network resource group name')
param virtualNetworkResourceGroupName string

@description('Image reference')
param imageReference object

@description('Authentication type')
param authenticationType string

@description('Linux configuration')
param linuxConfiguration object = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${adminUsername}/.ssh/authorized_keys'
        keyData: adminPasswordOrKey
      }
    ]
  }
}


@secure()
@description('Admin username')
param adminUsername string

@secure()
@description('Admin password or key')
param adminPasswordOrKey string


resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-03-01' existing = {
      name: '${virtualNetworkName}/${subnetName}'
      scope: resourceGroup(virtualNetworkResourceGroupName)
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2024-03-01' = {
  name: '${virtualMachineName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: virtualMachineName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  plan: {
    name: imageReference.sku
    product: imageReference.offer
    publisher: imageReference.publisher
  }
  properties: {
    hardwareProfile: {
      vmSize: virtualMachineSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: storageAccountType
        }
      }
      imageReference: imageReference
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    osProfile: {
      computerName: virtualMachineName
      adminUsername: adminUsername
      adminPassword: ((authenticationType == 'password') ? adminPasswordOrKey : null)
      linuxConfiguration: ((authenticationType == 'password') ? null : linuxConfiguration)
    }

  }
}

output serviceAssignedIdentityPrincipalId string = vm.identity.principalId
