using '../../bicep/main.bicep'

param virtualNetworkResourceGroupName = 'amlfs-rename-delete'
param virtualNetworkName = 'amlfs-rename-delete-vnet'
param authenticationType = 'password'
param subnetName = 'default'
param adminPasswordOrKey = readEnvironmentVariable('VM_PASSWORD')
param adminUsername = readEnvironmentVariable('VM_USERNAME')
param mysqlAdminLogin = readEnvironmentVariable('MYSQL_USERNAME')
param mysqlAdminPassword = readEnvironmentVariable('MYSQL_PASSWORD')
param virtualMachineName = 'azlfssync'
param storageAccountContainer = 'hsm'
param storageAccountName = 'amlfsrenamedelete'
param mySqlServerName = 'mysqlrobinhood'
