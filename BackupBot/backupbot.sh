#!/bin/bash

# Author: @pwnjack

# Source configuration file
source backup.conf

# Function to display usage information
usage() {
    echo "Usage: $0 -h <hosts_file> -p <passphrase_file> -k <ssh_key> -e <exclude_file> -b <backup_dir> -t <temp_dir> -l <log_file> [-s] [-v]" >&3
    echo
    echo "Options:" >&3
    echo "-h <hosts_file>        Path to the file containing the list of hosts to backup." >&3
    echo "-p <passphrase_file>   Path to the file containing the passphrase for encryption." >&3
    echo "-k <ssh_key>           Path to the SSH key for connecting to the remote hosts." >&3
    echo "-e <exclude_file>      Path to the file containing the list of files to exclude from the backup." >&3
    echo "-b <backup_dir>        Path to the directory where the backups should be stored." >&3
    echo "-t <temp_dir>          Path to the directory for storing temporary incremental backup data." >&3
    echo "-l <log_file>          Path to the file where logs should be written." >&3
    echo "-s                     Silent mode. Suppresses all output." >&3
    echo "-v                     Verbose mode. Outputs detailed information about the backup process." >&3
    exit 1
}

# Function to log messages with a timestamp
log_message() {
    local message_type=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$message_type]: $message" >&3
}

# Function to send an email alert using msmtp
send_email_alert() {
    local subject=$1
    local message=$2

    # Create the email headers and message
    local email_content
    email_content="Subject: $subject\nFrom: $EMAIL_SENDER\nTo: $ALERT_EMAIL\n\n$message"

    # Send the email using msmtp with a 10-second timeout
    if ! echo -e "$email_content" | msmtp --host="$SMTP_SERVER" --port="$SMTP_PORT" --timeout=10 --from="$EMAIL_SENDER" --add-missing-date-header --add-missing-from-header -t; then
        log_message "ERROR" "Failed to send email alert for $subject."
        return 1
    fi
    return 0
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

# Function to validate that all required files exist and are readable
validate_files() {
    local files=("$HOSTS_FILE" "$EXCLUDE_FILE" "$SSH_KEY" "$PASSPHRASE_FILE" "backup.conf")
    for file in "${files[@]}"; do
        if [[ ! -r $file ]]; then
            log_message "ERROR" "Error: '$file' does not exist or is not readable."
            exit 1
        fi
        validate_permissions "$file"
    done
}

# Function to handle SSH failures
handle_ssh_failure() {
    local remote_host=$1
    local attempt=$2
    local max_attempts=$3
    log_message "ERROR" "SSH failed for $remote_host, attempt $attempt of $max_attempts"
    sleep $delay
}

# Function to handle rsync failures
handle_rsync_failure() {
    local remote_host=$1
    local source_directory=$2
    log_message "ERROR" "rsync failed for $remote_host:$source_directory"
    sleep $delay
}

# Function to backup a single host with retry logic
backup_host() {
    local remote_host=$1
    local source_directory=$2
    local retries=3
    local delay=5
    local success=0

    for ((i=0; i<retries; i++)); do
        local host_name
        if ! host_name=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -n "$remote_host" "sudo hostname" 2>/dev/null); then
            handle_ssh_failure "$remote_host" "$((i + 1))" "$retries"
            continue
        fi

        local incremental_backup_dir="${TEMP_DIR}/${host_name}"
        mkdir -p "$incremental_backup_dir"
        chmod 700 "$incremental_backup_dir"

        local rsync_options=(--timeout=60 -a --delete --exclude-from="$EXCLUDE_FILE" -e "ssh -i \"$SSH_KEY\"" --rsync-path="sudo rsync")
        if [ "$VERBOSE_MODE" -eq 1 ]; then
            rsync_options+=(--progress --stats)
        fi

        if ! rsync "${rsync_options[@]}" "$remote_host:$source_directory" "$incremental_backup_dir"; then
            handle_rsync_failure "$remote_host" "$source_directory"
            continue
        fi

        local timestamp
        timestamp=$(date +%Y-%m-%d_%H-%M-%S)
        local backup_file="${BACKUP_DIR}/${host_name}_${timestamp}.tar.gz.gpg"
        local passphrase
        passphrase=$(<"$PASSPHRASE_FILE")

        if tar -czf - -C "$incremental_backup_dir" . | gpg --batch --yes --symmetric --passphrase "$passphrase" -o "$backup_file"; then
            log_message "INFO" "Backup and encryption completed for $host_name"
            success=1
            break
        else
            log_message "ERROR" "Backup encryption failed for $host_name"
            sleep $delay
        fi
    done

    if [[ $success -eq 0 ]]; then
        log_message "ERROR" "Backup ultimately failed for $remote_host after $retries attempts."
        return 1
    fi
}

# Setup file descriptor 3 to point to the console for user-visible messages
exec 3>&1

# Parse command-line options
while getopts ":h:p:k:e:b:t:l:sv" opt; do
    case $opt in
        h) HOSTS_FILE="$OPTARG" ;;
        p) PASSPHRASE_FILE="$OPTARG" ;;
        k) SSH_KEY="$OPTARG" ;;
        e) EXCLUDE_FILE="$OPTARG" ;;
        b) BACKUP_DIR="$OPTARG" ;;
        t) TEMP_DIR="$OPTARG" ;;
        l) LOG_FILE="$OPTARG" ;;
        s) SILENT_MODE=1 ;;
        v) VERBOSE_MODE=1 ;;
        *) usage ;;
    esac
done

# If no options were provided, display usage and exit
if [ $# -eq 0 ]; then
    usage
fi

# Validate and create TEMP_DIR if it does not exist
if [[ ! -d "$TEMP_DIR" ]]; then
    if ! mkdir -p "$TEMP_DIR"; then
        log_message "ERROR" "Unable to create temporary directory $TEMP_DIR."
        exit 1
    fi
    # Set permissions for TEMP_DIR to ensure it is secure
    chmod 700 "$TEMP_DIR"
fi

# Validate and create BACKUP_DIR if it does not exist
if [[ ! -d "$BACKUP_DIR" ]]; then
    if ! mkdir -p "$BACKUP_DIR"; then
        log_message "ERROR" "Unable to create backup directory $BACKUP_DIR."
        exit 1
    fi
fi

# Redirect output to log file and possibly to stdout
if [ "$SILENT_MODE" -eq 0 ]; then
    exec 1> >(tee -a "$LOG_FILE") 2>&1
else
    exec 1>>"$LOG_FILE" 2>&1
fi

# Validate the existence and permissions of required files
validate_files

# Initialize error count
error_count=0

# Read each line from the hosts file and perform a backup
while IFS= read -r line || [[ -n "$line" ]]; do
    IFS=' ' read -r remote_host source_directory <<< "$line"
    if ! backup_host "$remote_host" "$source_directory"; then
        log_message "ERROR" "Backup failed for $remote_host. See previous messages for details."
        ((error_count++))
        # Send an email alert due to backup failure
        if ! send_email_alert "Backup Failed" "Backup failed for $remote_host. Check the logs at $LOG_FILE for more information."; then
            log_message "ERROR" "Failed to send email alert for $remote_host."
        fi
    fi
done < "$HOSTS_FILE"

# Final log message indicating the completion status of the script
if [ "$error_count" -gt 0 ]; then
    log_message "ERROR" "Backup script completed with $error_count errors."
    send_email_alert "Backup Completed with Errors" "Backup script completed with $error_count errors. Check the logs at $LOG_FILE for more information."
    exit 1
else
    log_message "INFO" "Backup script completed successfully."
    send_email_alert "Backup Completed Successfully" "Backup script completed successfully. Check the logs at $LOG_FILE for more information."
fi

exit 0
