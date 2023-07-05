#!/bin/bash

# This script performs a daily or monthly backup of Tableau Server data and configuration.
# It generates ziplogs, creates repository and configuration backup files, and copies these
# files to a local archive location and an AWS S3 bucket. The script also deletes old backup
# files based on specified retention periods.
#
# Usage: tableau_backup_daily.sh [OPTION]
#
# Options:
#   --monthly, -M   Perform a monthly backup instead of a daily backup
#   --help, -H      Display this help message and exit
#
# --------
# Examples of how to call the script for daily and monthly backups:
# --------
# To perform a daily backup, you can call the script without any parameters:
# ./tableau_backup_daily.sh
# 
# To perform a monthly backup, you can call the script with the --monthly or -M parameter:
# ./tableau_backup_daily.sh --monthly
#   or
# ./tableau_backup_daily.sh -M
# 


# **************************************** INPUT VARIABLES ****************************************

# Set the path on the local server where copies of the backups will be stored
# best practice is to be offline / on another server
local_path="/var/opt/tableau/backups/Daily/"

# Set the AWS S3 location where backup files will be stored
destination_path="s3://my-s3-bucket/tableau-backups/"

# Set the backup retention value (in days). Files older than this value will be deleted.
backup_retention_days=14
# Set the monthly backup retention value (in months). Files older than this value will be deleted.
backup_retention_months=12

# Set the ziplog retention value (in days). Files older than this value will be deleted when running the tsm maintenance cleanup command.
ziplog_retention=3

# **************************************** SET VARIABLES ****************************************

# Set timestamp with current date/time and format as YYYY-MMDD-HHmm
ts=$(date +'%Y-%m%d-%H%M')

# Set the name of the server that is to be backed up
backup_server=$(hostname)
# Set the name of the audit log file
audit_log_file="$local_path$backup_server-$ts-backup-log.txt"

# check if end of month (next day is 1st of month)
date_type="Daily"
if [[ $(date -d tomorrow +'%d') == "01" ]]; then
    date_type="Monthly"
fi

# check for optional parameters
while [[ $# -gt 0 ]]; do
    case $1 in
        --monthly|-M)
            date_type="Monthly"
            shift # past argument
            ;;
        --help|-H)
            echo "Usage: tableau_backup_daily.sh [OPTION]"
            echo "Backup Tableau Server data and configuration."
            echo ""
            echo "Options:"
            echo "  --monthly, -M   Perform a monthly backup instead of a daily backup"
            echo "  --help, -H      Display this help message and exit"
            exit 0
            ;;
        *)
            shift # past argument
            ;;
    esac
done

# update local path (to keep monthly backups separated)
local_path=${local_path/Daily/$date_type}

# **************************************** FOLDER CHECK ****************************************

if [[ ! -d "$local_path" ]]; then
    mkdir -p "$local_path"
    if [[ $? -ne 0 ]]; then
        echo "Failed to create local folder: $local_path"
        exit 1
    fi
fi

# Set the name of the ziplogs files
# Note the ziplogs file will be written to the location specified in the basefilepath.log_archive variable
ziplogs_name="$backup_server-$ts-ziplogs.zip"

# Get location of the ziplogs files, convert to a string, and then replace the forward slashes with backward slashes
ziplogs_directory=$(tsm configuration get -k basefilepath.log_archive)

# Create full file name and path to the ziplogs file
ziplogs_file="$ziplogs_directory/$ziplogs_name"

# Set the name of the repository backup file
# Note the repository backup files will be written to the location specified in the basefilepath.backuprestore variable
repositorybackup_name="$backup_server-$ts-backup.tsbak"

# Get location of the repository backup files, convert to a string, and then replace the forward slashes with backward slashes
repositorybackup_directory=$(tsm configuration get -k basefilepath.backuprestore)

# Create full file name and path to the ziplogs file
repositorybackup_file="$repositorybackup_directory/$repositorybackup_name"

# Set the name of the configuration backup file
configbackup_file="$local_path$backup_server-$ts-config.json"



# **************************************** Write to Audit Log ****************************************

echo "************************************************" >> $audit_log_file
echo $(date) >> $audit_log_file
echo "$date_type backup started." >> $audit_log_file
echo "************************************************" >> $audit_log_file
echo "Input variables..." >> $audit_log_file
echo "*******************" >> $audit_log_file
echo "dest_path = '$dest_path'" >> $audit_log_file
echo "backup_retention_days = '$backup_retention_days'" >> $audit_log_file
echo "backup_retention_months = '$backup_retention_months'" >> $audit_log_file
echo "ziplog_retention = '$ziplog_retention'" >> $audit_log_file
echo "configbackup_path = '$configbackup_path'" >> $audit_log_file
echo "" >> $audit_log_file
echo "Setting variables..." >> $audit_log_file
echo "*******************" >> $audit_log_file
echo "ts = '$ts'" >> $audit_log_file
echo "backup_server = '$backup_server'" >> $audit_log_file
echo "ziplogs_file = '$ziplogs_file'" >> $audit_log_file
echo "repositorybackup_file = '$repositorybackup_file'" >> $audit_log_file
echo "configbackup_file = '$configbackup_file'" >> $audit_log_file
echo "" >> $audit_log_file

# ************************************************ GENERATE ZIPLOGS ************************************************

# Zip the log files using the following options:
#     --with-postgresql-data   include the PostgreSQL data folder if Tableau Server is stopped or PostgreSQL dump files if Tableau Server is running
#     --file   specify the name for the zipped archive file (for this script, the format for the name is logs-YYYY-MMDD-HHMM.zip)
#     --description    provides a description that appears in the Description field on the Maintenance page in the TSM web UI
#     --with-msinfo   include the msinfo32 report, with system information about OS, hardware, and running software
#     --with-latest-dump   include latest dumps
#     --minimumdate Earliest date of log files to be included. If not specified, a maximum of two days of log files are included. Format of date should be "mm/dd/yyyy".
#     --overwrite For an overwrite of an existing ziplog file. If a file by the same name already exists and this option is not used, the ziplogs command will fail.
#     --request-timeout Wait the specified amount of time for the command to finish. Default value is 1800 (30 minutes).
#     --with-netstat-info include netstat information

# Note that ziplogs will be written to the location specified in the basefilepath.log_archive variable

echo "************************************************" >> $audit_log_file
echo $(date) >> $audit_log_file
echo "Creating ziplog files..." >> $audit_log_file

tsm maintenance ziplogs --with-postgresql-data --file $ziplogs_name --description "Logs from Daily Backup" --with-latest-dump --with-netstat-info

echo "" >> $audit_log_file

# Copy ziplogs files to archive location

echo "************************************************" >> $audit_log_file
echo $(date) >> $audit_log_file



# ************************************************ BACKUP REPOSITORY AND CONFIGURATION DATA ************************************************

# Delete repository and configuration backup files older than the $date_limit
echo "************************************************" >> $audit_log_file
echo $(date) >> $audit_log_file
echo "Removing backup files older than '$date_limit' ..." >> $audit_log_file

find $repositorybackup_directory -name "*.tsbak" -type f -mtime +$backup_retention_days -delete
find $repositorybackup_directory -name "*.json" -type f -mtime +$backup_retention_days -delete
find $ziplogs_directory -name "*.zip" -type f -mtime +$backup_retention_days -delete

# remove older files from archive location ($local_path)
echo "Removing backup files from archive location, older than '$date_limit' ..." >> $audit_log_file
find $local_path -name "*.tsbak" -type f -mtime +$backup_retention_days -delete
find $local_path -name "*.json" -type f -mtime +$backup_retention_days -delete
find $local_path -name "*.zip" -type f -mtime +$backup_retention_days -delete
find $local_path -name "*log.txt" -type f -mtime +$backup_retention_days -delete

echo "" >> $audit_log_file

# Create a backup files using this option:
#     -f   write the backup to the specified file name

echo "************************************************" >> $audit_log_file
echo $(date) >> $audit_log_file
echo "Creating repository backup file..." >> $audit_log_file

tsm maintenance backup -f $repositorybackup_name

echo "" >> $audit_log_file

echo "************************************************" >> $audit_log_file
echo $(date) >> $audit_log_file
echo "Creating config backup file..." >> $audit_log_file

tsm settings export -f $configbackup_file

echo "" >> $audit_log_file

# Copy repository and configuration backup files to archive location

echo "************************************************" >> $audit_log_file
echo $(date) >> $audit_log_file
echo "Copying backup files to archive location ($local_path)..." >> $audit_log_file

cp $repositorybackup_file $local_path
cp $configbackup_file $local_path

# Move all backup and ziplog files in the tableau backup repository and ziplog archive to the local_path destination except for the current files
repository_files_moved=$(find $repositorybackup_directory -name "*.tsbak" -type f ! -name "$repositorybackup_name" -exec mv {} $local_path \; | wc -l)
ziplog_files_moved=$(find $ziplogs_directory -name "*.zip" -type f ! -name "$ziplogs_name" -exec mv {} $local_path \; | wc -l)

echo "Moved $repository_files_moved repository backup files and $ziplog_files_moved ziplog files from the tableau backup repository and ziplog archive to the local_path destination." >> $audit_log_file

echo "" >> $audit_log_file

# **************************************** AWS S3 Backup File Sync ****************************************
echo "Copying backup files to AWS S3 archive location ($destination_path)..." >> $audit_log_file

aws s3 cp "$local_path" "$destination_path" --recursive --exclude "*" --include "*.tsbak" --include "*.json"

echo "************************************************" >> $audit_log_file
echo $(date) >> $audit_log_file
echo "$date_type backup complete." >> $audit_log_file

