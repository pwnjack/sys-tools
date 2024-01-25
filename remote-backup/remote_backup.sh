#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 -h <hosts_file> -p <passphrase_file> -k <ssh_key> -e <exclude_file> -b <backup_dir> -l <log_file> [-s]" >&3
    echo
    echo "Options:"
    echo "-h <hosts_file>        Path to the file containing the list of hosts to backup."
    echo "-p <passphrase_file>   Path to the file containing the passphrase for encryption."
    echo "-k <ssh_key>           Path to the SSH key for connecting to the remote hosts."
    echo "-e <exclude_file>      Path to the file containing the list of files to exclude from the backup."
    echo "-b <backup_dir>        Path to the directory where the backups should be stored."
    echo "-l <log_file>          Path to the file where logs should be written."
    echo "-s                     Silent mode. Suppresses all output."
    echo >&3
    exit 1
}

# Set default variables
HOSTS_FILE="hosts.txt"
PASSPHRASE_FILE="passphrase.txt"
SSH_KEY="$HOME/.ssh/id_rsa"
EXCLUDE_FILE="exclude.txt"
BACKUP_DIR="backups"
LOG_FILE="backup.log"
SILENT_MODE=0

# Setup file descriptor 3 to point to the console
exec 3>&1

# Parse options
while getopts ":h:p:k:e:b:l:s" opt; do
    case $opt in
        h) HOSTS_FILE="$OPTARG" ;;
        p) PASSPHRASE_FILE="$OPTARG" ;;
        k) SSH_KEY="$OPTARG" ;;
        e) EXCLUDE_FILE="$OPTARG" ;;
        b) BACKUP_DIR="$OPTARG" ;;
        l) LOG_FILE="$OPTARG" ;;
        s) SILENT_MODE=1 ;;
        *) usage ;;
    esac
done

# Redirect output to log file and possibly to stdout
if [ $SILENT_MODE -eq 0 ]; then
    exec 1> >(tee -a "$LOG_FILE") 2>&1
else
    exec 1>>"$LOG_FILE" 2>&1
fi

# Function to log messages
log_message() {
    local message_type=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$message_type]: $message" >&3
}

# Function to validate file permissions
validate_permissions() {
    local file=$1
    local permissions
    permissions=$(stat -c "%a" "$file")
    if [ "$permissions" -gt "600" ]; then
        log_message "ERROR" "Permissions for $file are too open. It is recommended to use 'chmod 600 $file' to set proper permissions."
        exit 1
    fi
}

# Function to validate that all files exist and are readable
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

# Function to backup a single host
backup_host() {
    local ssh_conn=$1
    local src_dir=$2
    local host_name
    host_name=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -n "$ssh_conn" "sudo hostname" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "SSH failed for $ssh_conn"
        return 1
    fi

    local backup_file="${BACKUP_DIR}/${host_name}_$(date +%Y-%m-%d_%H-%M-%S).tar.gz.gpg"
    local passphrase
    passphrase=$(<"$PASSPHRASE_FILE")

    if ! rsync --timeout=10 -a --delete --exclude-from="$EXCLUDE_FILE" -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" --rsync-path="sudo rsync" "$ssh_conn:$src_dir" "/tmp/${host_name}/"; then
        log_message "ERROR" "rsync failed for $ssh_conn:$src_dir"
        return 1
    fi

    if ! tar -czf - -C "/tmp" "$host_name" | gpg --batch --yes --symmetric --passphrase "$passphrase" -o "$backup_file"; then
        log_message "ERROR" "Backup encryption failed for $host_name"
        return 1
    fi

    rm -rf "/tmp/${host_name}"
    log_message "INFO" "Backup and cleanup completed for $host_name"
}

# Main script execution
if [ $# -eq 0 ]; then
    usage
fi

validate_files

error_count=0

while IFS= read -r line || [[ -n "$line" ]]; do
    IFS=' ' read -r ssh_conn src_dir <<< "$line"
    if ! backup_host "$ssh_conn" "$src_dir"; then
        log_message "ERROR" "Backup failed for $ssh_conn. See previous messages for details."
        ((error_count++))
        # Decide what action to take here: exit, continue, retry, etc.
    fi
done < "$HOSTS_FILE"

if [ $error_count -gt 0 ]; then
    log_message "ERROR" "Backup script completed with $error_count errors."
    exit 1
else
    log_message "INFO" "Backup script completed successfully."
fi