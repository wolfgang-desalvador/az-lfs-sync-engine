param virtualMachineName string
param location string
param deploymentName string
param lfsMount string
param storageAccountName string
param storageContainerName string
param changelogId string
param mysqlAdminLogin string
@secure()
param mysqlAdminPassword string
param mysqlServer string

resource VM 'Microsoft.Compute/virtualMachines@2022-11-01' existing = {
  name: virtualMachineName
  scope: resourceGroup()
}

var script = '''
set +e
yum install -y python38
rm -rf /opt/az_lfs/
python3.8 -m venv /opt/az_lfs
source /opt/az_lfs/bin/activate
pip install --upgrade pip

wget "https://github.com/wolfgang-desalvador/az-lfs-hsm-remove/releases/download/0.0.5/az_lfs_hsm_remove-0.0.5-py3-none-any.whl"
pip install az_lfs_hsm_remove-0.0.4-py3-none-any.whl

wget "https://github.com/wolfgang-desalvador/az-lfs-hsm-release/releases/download/0.0.2/az_lfs_hsm_release-0.0.2-py3-none-any.whl" -O az_lfs_hsm_release-0.0.2-py3-none-any.whl
pip install az_lfs_hsm_release-0.0.2-py3-none-any.whl

cat << "EOF" > /usr/sbin/lfs_hsm_remove.sh
#!/bin/bash
fullpath="$1"
 
/opt/az_lfs/bin/az_lfs_hsm_remove ${fullpath} --force
EOF

cat << "EOF" > /usr/sbin/lfs_hsm_release.sh
#!/bin/bash
fullpath="$1"
 
/opt/az_lfs/bin/az_lfs_hsm_release ${fullpath}
EOF

cat << EOF > /etc/az_lfs_hsm_remove.json
{
    "accountURL": "https://${storage_account}.blob.core.windows.net/",
    "containerName": "${storage_container}"
}
EOF

cat << EOF > /etc/az_lfs_hsm_release.json
{
    "accountURL": "https://${storage_account}.blob.core.windows.net/",
    "containerName": "${storage_container}"
}
EOF



######### Install Lustre Client including Devel. Please adjust version if newer is available
yum groupinstall -y "Development Tools"
yum install -y lustre-client-2.15.4_42_gd6d405d-devel
yum install -y git autogen rpm-build autoconf automake gcc libtool glib2-devel libattr-devel mailx bison flex
yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
yum install -y jemalloc-devel
yum remove mariadb-* -y
yum install -y mysql-devel
yum remove robinhood* -y
yum remove robinhood-* -y

cd /root/
rm -rf robinhood

git clone https://github.com/wolfgang-desalvador/robinhood.git
cd robinhood

sed -i "s/php-mysql/php-mysqlnd/g" ./robinhood.spec.in

sed -i "s/lpackage lustre-client/lpackage lustre-client-2.15.4_42_gd6d405d/g" ./robinhood.spec.in


sh autogen.sh
./configure --enable-lustre

make rpm
yum localinstall -y rpms/RPMS/x86_64/robinhood-*


echo ${mysql_password} > /etc/robinhood.d/.dbpassword
chmod 600 /etc/robinhood.d/.dbpassword

rbh_log_rotate_file="/etc/logrotate.d/robinhood"
cat <<EOF > $rbh_log_rotate_file
/var/log/robinhood*.log {
    compress
    weekly
    rotate 6
    notifempty
    missingok
    copytruncate
}
EOF
chmod 644 $rbh_log_rotate_file


cat <<EOF > /etc/robinhood.d/lustre.conf
# -*- mode: c; c-basic-offset: 4; indent-tabs-mode: nil; -*-
# vim:expandtab:shiftwidth=4:tabstop=4:

General
{
    fs_path = "$lfs_mount";
    fs_type = lustre;
    stay_in_fs = yes;
    check_mounted = yes;
    last_access_only_atime = no;
    uid_gid_as_numbers = no;
}

# logs configuration
Log
{
    # log levels: CRIT, MAJOR, EVENT, VERB, DEBUG, FULL
    debug_level = EVENT;

    # Log file
    log_file = "/var/log/robinhood.log";

    # File for reporting purge events
    report_file = "/var/log/robinhood_actions.log";
    alert_file = "/var/log/robinhood_alerts.log";
    changelogs_file = "/var/log/robinhood_cl.log";

    stats_interval = 5min;

    batch_alert_max = 5000;
    alert_show_attrs = yes;
    log_procname = yes;
    log_hostname = yes;
}

# updt params configuration
db_update_params
{
    # possible policies for refreshing metadata and path in database:
    #   never: get the information once, then never refresh it
    #   always: always update entry info when processing it
    #   on_event: only update on related event
    #   periodic(interval): only update periodically
    #   on_event_periodic(min_interval,max_interval)= on_event + periodic

    # Updating of file metadata
    md_update = always ;
    # Updating file path in database
    path_update = on_event_periodic(0,1h) ;
    # File classes matching
    fileclass_update = always ;
}

# list manager configuration
ListManager
{
    # Method for committing information to database.
    # Possible values are:
    # - "autocommit": weak transactions (more efficient, but database inconsistencies may occur)
    # - "transaction": manage operations in transactions (best consistency, lower performance)
    # - "periodic(<nb_transaction>)": periodically commit (every <n> transactions).
    commit_behavior = transaction ;

    # Minimum time (in seconds) to wait before trying to reestablish a lost connection.
    # Then this time is multiplied by 2 until reaching connect_retry_interval_max
    connect_retry_interval_min = 1 ;
    connect_retry_interval_max = 30 ;
    # disable the following options if you are not interested in
    # user or group stats (to speed up scan)
    accounting  = enabled ;

    MySQL
    {
        server = "${mysql_server}" ;
        db     = "lustre" ;
        user   = "${mysql_username}" ;
        password_file = "/etc/robinhood.d/.dbpassword" ;
        # port   = 3306 ;
        # socket = "/tmp/mysql.sock" ;
        engine = InnoDB ;
    }
}

# entry processor configuration
EntryProcessor
{
    # nbr of worker threads for processing pipeline tasks
    nb_threads = 16 ;

    # Max number of operations in the Entry Processor pipeline.
    # If the number of pending operations exceeds this limit, 
    # info collectors are suspended until this count decreases
    max_pending_operations = 100 ;

    # max batched DB operations (1=no batching)
    max_batch_size = 100;

    # Optionnaly specify a maximum thread count for each stage of the pipeline:
    # <stagename>_threads_max = <n> (0: use default)
    # STAGE_GET_FID_threads_max = 4 ;
    # STAGE_GET_INFO_DB_threads_max     = 4 ;
    # STAGE_GET_INFO_FS_threads_max     = 4 ;
    # STAGE_PRE_APPLY_threads_max       = 4 ;
    # Disable batching (max_batch_size=1) or accounting (accounting=no)
    # to allow parallelizing the following step:
    # STAGE_DB_APPLY_threads_max        = 4 ;

    # if set to 'no', classes will only be matched
    # at policy application time (not during a scan or reading changelog)
    match_classes = yes;

    # Faking mtime to an old time causes the file to be migrated
    # with top priority. Enabling this parameter detect this behavior
    # and doesn't allow  mtime < creation_time
    detect_fake_mtime = no;
}

# FS scan configuration
FS_Scan
{
    # simple scan interval (fixed)
    scan_interval      =   2d ;

    # min/max for adaptive scan interval:
    # the more the filesystem is full, the more frequently it is scanned.
    #min_scan_interval      =   24h ;
    #max_scan_interval      =    7d ;

    # number of threads used for scanning the filesystem
    nb_threads_scan        =     2 ;

    # when a scan fails, this is the delay before retrying
    scan_retry_delay       =    1h ;

    # timeout for operations on the filesystem
    scan_op_timeout        =    1h ;
    # exit if operation timeout is reached?
    exit_on_timeout        =    yes ;
    # external command called on scan termination
    # special arguments can be specified: {cfg} = config file path,
    # {fspath} = path to managed filesystem
    #completion_command     =    "/path/to/my/script.sh -f {cfg} -p {fspath}" ;

    # Internal scheduler granularity (for testing and of scan, hangs, ...)
    spooler_check_interval =  1min ;

    # Memory preallocation parameters
    nb_prealloc_tasks      =   256 ;

    Ignore
    {
        # ignore ".snapshot" and ".snapdir" directories (don't scan them)
        type == directory
        and
        ( name == ".snapdir" or name == ".snapshot" )
    }
}

# changelog reader configuration
# Parameters for processing MDT changelogs :
ChangeLog
{
    # 1 MDT block for each MDT :
    MDT
    {
        # name of the first MDT
        mdt_name  = "MDT0000" ;

        # id of the persistent changelog reader
        # as returned by "lctl changelog_register" command
        reader_id = "${changelogId}" ;
    }

    # clear changelog every 1024 records:
    batch_ack_count = 1024 ;

    force_polling    = yes ;
    polling_interval = 1s ;
    # changelog batching parameters
    queue_max_size   = 1000 ;
    queue_max_age    = 5s ;
    queue_check_interval = 1s ;
    # delays to update last committed record in the DB
    commit_update_max_delay = 5s ;
    commit_update_max_delta = 10k ;

    # uncomment to dump all changelog records to the file
}

# policies configuration
# Load policy definitions for Lustre/HSM
%include "includes/lhsm.inc"

#### Fileclasses definitions ####

FileClass small_files {
    definition { type == file and size >= 0 and size <= 16MB }
    # report = yes (default)
}
FileClass std_files {
    definition { type == file and size > 16MB and size <= 1GB }
}
FileClass big_files {
    definition { type == file and size > 1GB }
}

lhsm_config {
    # used for 'undelete': command to change the fid of an entry in archive
    rebind_cmd = "/usr/sbin/lhsmtool_posix --hsm_root=/tmp/backend --archive {archive_id} --rebind {oldfid} {newfid} {fsroot}";
}

lhsm_archive_parameters {
    nb_threads = 1;

    # limit archive rate to avoid flooding the MDT coordinator
    schedulers = common.rate_limit;
    rate_limit {
        # max count per period
        max_count = 1000;
        # max size per period: 1GB/s
        max_size = 60GB;
        # period, in milliseconds: 10s
        period_ms = 10000;
    }

    # suspend policy run if action error rate > 50% (after 100 errors)
    suspend_error_pct = 50%;
    suspend_error_min= 100;

    # overrides policy default action
    action = cmd("lfs hsm_archive --archive {archive_id} ${lfs_mount}/.lustre/fid/{fid}");

    # default action parameters
    action_params {
        archive_id = 1;
    }
}

lhsm_archive_rules {
    rule archive_small {
        target_fileclass = small_files;
        condition { last_mod >= 2y }
    }

    rule archive_std {
        target_fileclass = std_files;
        target_fileclass = big_files;
        condition { last_mod >= 30min }
    }

    # fallback rule
    rule default {
        condition { last_mod >= 2h }
    }
}

# run every 5 min
lhsm_archive_trigger {
    trigger_on = periodic;
    check_interval = 5min;
}

#### Lustre/HSM release configuration ####

#lhsm_release_rules {
#    # keep small files on disk as long as possible
#    rule release_small {
#        target_fileclass = small_files;
#        condition { last_access > 1y }
#    }

#    rule release_std {
#        target_fileclass = std_files;
#        target_fileclass = big_files;
#        condition { last_access > 1d }
#    }
#
#    # fallback rule
#    rule default {
#        condition { last_access > 6h }
#    }
#}

# run 'lhsm_release' on full OSTs
#lhsm_release_trigger {
#    trigger_on = ost_usage;
#    high_threshold_pct = 85%;
#    low_threshold_pct  = 80%;
#    check_interval     = 5min;
#}

#lhsm_release_parameters {
#     action = cmd("/usr/sbin/lfs_hsm_release.sh {fullpath}");
#    nb_threads = 4;
### purge 1000 files max at once
##    max_action_count = 1000;
##    max_action_volume = 1TB;

#    # suspend policy run if action error rate > 50% (after 100 errors)
#    suspend_error_pct = 50%;
#    suspend_error_min= 100;
#}

lhsm_remove_parameters
{
    # overrides policy default action
    action = cmd("/usr/sbin/lfs_hsm_remove.sh {fullpath}");

    # default action parameters
    action_params {
        archive_id = 1;
    } 
}

#### Lustre/HSM remove configuration ####
lhsm_remove_rules
{
    # cleanup backend files after 5m
    rule default {
        condition { rm_time >= 5m }
    }
}

# run daily
lhsm_remove_trigger
{
    trigger_on = periodic;
    check_interval = 5m;
}
EOF

mysql -u ${mysql_username} --password=$(cat /etc/robinhood.d/.dbpassword) -h ${mysql_server} -e "create database lustre;"
dnf install azure-cli -y
az mysql flexible-server parameter set --name sql_generate_invisible_primary_key --resource-group ${resource_group} --server-name ${mysql_username} --value OFF
'''

resource installRobinhood 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = {
  parent: VM
  name: deploymentName
  location: location
  properties: {
    protectedParameters: [
      {
        name: 'mysql_server'
        value: mysqlServer
      }
      {
        name: 'mysql_username'
        value: mysqlAdminLogin
      }
      {
        name: 'mysql_password'
        value: mysqlAdminPassword
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
      {
        name: 'lfs_mount'
        value: lfsMount
      }
    ]
    source: {
      script: script
    }
    timeoutInSeconds: 300
  }
}
