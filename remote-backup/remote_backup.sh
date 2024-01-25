#!/bin/bash

# This script performs incremental backups of remote hosts, encrypts the backup,
# and maintains a local copy of the last backup state for efficient future backups.

# Function to display usage information
usage() {
    # Direct output to file descriptor 3 to ensure it's visible to the user
    echo "Usage: $0 -h <hosts_file> -p <passphrase_file> -k <ssh_key> -e <exclude_file> -b <backup_dir> -t <temp_dir> -l <log_file> [-s]" >&3
    echo
    echo "Options:"
    echo "-h <hosts_file>        Path to the file containing the list of hosts to backup."
    echo "-p <passphrase_file>   Path to the file containing the passphrase for encryption."
    echo "-k <ssh_key>           Path to the SSH key for connecting to the remote hosts."
    echo "-e <exclude_file>      Path to the file containing the list of files to exclude from the backup."
    echo "-b <backup_dir>        Path to the directory where the backups should be stored."
    echo "-t <temp_dir>          Path to the directory for storing temporary incremental backup data."
    echo "-l <log_file>          Path to the file where logs should be written."
    echo "-s                     Silent mode. Suppresses all output."
    echo >&3
    exit 1
}

ALERT_EMAIL="admin@example.com"

# Default variable settings
HOSTS_FILE="hosts.txt"
PASSPHRASE_FILE="passphrase.txt"
SSH_KEY="$HOME/.ssh/id_rsa"
EXCLUDE_FILE="exclude.txt"
BACKUP_DIR="backups"
TEMP_DIR="/var/tmp"  # Default temporary directory for incremental backups
LOG_FILE="backup.log"
SILENT_MODE=0

# Setup file descriptor 3 to point to the console for user-visible messages
exec 3>&1

# Parse command-line options
while getopts ":h:p:k:e:b:t:l:s" opt; do
    case $opt in
        h) HOSTS_FILE="$OPTARG" ;;
        p) PASSPHRASE_FILE="$OPTARG" ;;
        k) SSH_KEY="$OPTARG" ;;
        e) EXCLUDE_FILE="$OPTARG" ;;
        b) BACKUP_DIR="$OPTARG" ;;
        t) TEMP_DIR="$OPTARG" ;;  # Assign user-specified temporary directory
        l) LOG_FILE="$OPTARG" ;;
        s) SILENT_MODE=1 ;;
        *) usage ;;
    esac
done

# Validate and create TEMP_DIR if it does not exist
if [[ ! -d "$TEMP_DIR" ]]; then
    mkdir -p "$TEMP_DIR"
    if [[ $? -ne 0 ]]; then
        echo "Error: Unable to create temporary directory $TEMP_DIR." >&2
        exit 1
    fi
fi

# Set permissions for TEMP_DIR to ensure it is secure
chmod 700 "$TEMP_DIR"

# Redirect output to log file and possibly to stdout
if [ $SILENT_MODE -eq 0 ]; then
    # Output to both stdout and log file
    exec 1> >(tee -a "$LOG_FILE") 2>&1
else
    # Output only to log file
    exec 1>>"$LOG_FILE" 2>&1
fi

# Function to log messages with a timestamp
log_message() {
    local message_type=$1
    local message=$2
    # Log messages are directed to file descriptor 3
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$message_type]: $message" >&3
}

# Function to send an email alert
send_email_alert() {
    local subject=$1
    local message=$2
    echo "$message" | mail -s "$subject" "$ALERT_EMAIL"
}

# Function to validate file permissions
validate_permissions() {
    local file=$1
    local permissions
    permissions=$(stat -c "%a" "$file")
    # Ensure permissions are not too open
    if [ "$permissions" -gt "600" ]; then
        log_message "ERROR" "Permissions for $file are too open. It is recommended to use 'chmod 600 $file' to set proper permissions."
        exit 1
    fi
}

# Function to validate that all required files exist and are readable
validate_files() {
    local files=("$HOSTS_FILE" "$EXCLUDE_FILE" "$SSH_KEY" "$PASSPHRASE_FILE")
    for file in "${files[@]}"; do
        if [[ ! -r $file ]]; then
            log_message "ERROR" "Error: '$file' does not exist or is not readable."
            exit 1
        fi
        validate_permissions "$file"
    done
}

# Function to backup a single host with retry logic
backup_host() {
    local ssh_conn=$1
    local src_dir=$2
    local retries=3
    local delay=5
    local success=0

    # Attempt to backup the host with the specified number of retries
    for ((i=0; i<retries; i++)); do
        # Fetch the hostname for identification purposes
        local host_name
        host_name=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -n "$ssh_conn" "sudo hostname" 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            log_message "ERROR" "SSH failed for $ssh_conn, attempt $(($i + 1)) of $retries"
            sleep $delay
            continue
        fi

        # Create a directory for incremental backups if it doesn't exist
        local incremental_backup_dir="${TEMP_DIR}/${host_name}_incremental"
        mkdir -p "$incremental_backup_dir"
        chmod 700 "$incremental_backup_dir"  # Secure the directory

        # Perform rsync for incremental backup
        if ! rsync --timeout=60 -a --delete --exclude-from="$EXCLUDE_FILE" -e "ssh -i $SSH_KEY" "$ssh_conn:$src_dir" "$incremental_backup_dir"; then
            log_message "ERROR" "rsync failed for $ssh_conn:$src_dir"
            sleep $delay
            continue
        fi

        # Create a timestamped backup file name
        local timestamp=$(date +%Y-%m-%d_%H-%M-%S)
        local backup_file="${BACKUP_DIR}/${host_name}_${timestamp}.tar.gz.gpg"
        local passphrase
        passphrase=$(<"$PASSPHRASE_FILE")

        # Archive and encrypt the incremental backup directory
        if tar -czf - -C "$incremental_backup_dir" . | gpg --batch --yes --symmetric --passphrase "$passphrase" -o "$backup_file"; then
            log_message "INFO" "Backup and encryption completed for $host_name"
            success=1
            break
        else
            log_message "ERROR" "Backup encryption failed for $host_name"
            sleep $delay
        fi
    done

    # Check if the backup was successful after all retries
    if [[ $success -eq 0 ]]; then
        log_message "ERROR" "Backup ultimately failed for $ssh_conn after $retries attempts."
        return 1
    fi
}

# Main script execution starts here
if [ $# -eq 0 ]; then
    usage
fi

# Validate the existence and permissions of required files
validate_files

# Initialize error count
error_count=0

# Read each line from the hosts file and perform a backup
while IFS= read -r line || [[ -n "$line" ]]; do
    IFS=' ' read -r ssh_conn src_dir <<< "$line"
    if ! backup_host "$ssh_conn" "$src_dir"; then
        log_message "ERROR" "Backup failed for $ssh_conn. See previous messages for details."
        send_email_alert "Backup Failed" "Backup failed for $ssh_conn. Check the logs at $LOG_FILE for more information."
        ((error_count++))
    fi
done < "$HOSTS_FILE"

# Final log message indicating the completion status of the script
if [ $error_count -gt 0 ]; then
    log_message "ERROR" "Backup script completed with $error_count errors."
    exit 1
else
    log_message "INFO" "Backup script completed successfully."
fi