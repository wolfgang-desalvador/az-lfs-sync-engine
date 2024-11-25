param virtualMachineName string
param location string
param deploymentName string
param lfsMount string
param storageAccountName string
param storageContainerName string
param changelogId string


resource VM 'Microsoft.Compute/virtualMachines@2022-11-01'  existing = {
  name: virtualMachineName
  scope: resourceGroup()
}

var script = '''
set +e
# we still need to disable selinux for the lustremetasync to work
setenforce 0
sed -i 's/SELINUX=.*$/SELINUX=disabled/g' /etc/selinux/config
rm -rf /sbin/changelog-reader
wget "https://github.com/edwardsp/LustreAzureSync/releases/download/v1.0.4/LustreAzureSync" -O /sbin/changelog-reader
chmod +x /sbin/changelog-reader
lustremetasync_systemd_file="/lib/systemd/system/lustremetasync.service"
cat <<EOF > $lustremetasync_systemd_file
[Unit]
Description=Handling directory/meta data backup on Lustre filesystem.
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=simple
ExecStart=/sbin/changelog-reader -mountroot "${lfs_mount}" -maxretries 1 -account "${storage_account}" -container "${storage_container}" -mdt lustrefs-MDT0000 -userid ${changelogId}
Restart=always
StandardOutput=append:/var/log/lustremetasync.log
StandardError=inherit

[Install]
WantedBy=multi-user.target
EOF
chmod 600 $lustremetasync_systemd_file
lustremetasync_log_rotate_file="/etc/logrotate.d/lustremetasync"
cat <<EOF > $lustremetasync_log_rotate_file
/var/log/lustremetasync.log {
    compress
    weekly
    rotate 6
    notifempty
    missingok
    copytruncate
}
EOF
chmod 644 $lustremetasync_log_rotate_file
systemctl daemon-reload
'''



resource installLustreMetaSync 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = {
  parent: VM
  name: deploymentName
  location: location
  properties: {
    protectedParameters: [
      {
        name: 'lfs_mount'
        value: lfsMount
      }
      {
        name: 'storage_account'
        value: storageAccountName
      }
      {
        name: 'storage_container'
        value: storageContainerName
      }
      {
        name: 'changelogId'
        value: changelogId
      }
    ]
    source: {
      script: script
    }
    timeoutInSeconds: 300
  }
}
