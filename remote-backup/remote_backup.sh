#!/bin/bash

usage() {
    echo "Usage: $0 -h <hosts_file> -p <passphrase_file> -k <ssh_key> -e <exclude_file> -b <backup_dir> -l <log_file>"
    echo
    echo "Options:"
    echo "-h <hosts_file>        Path to the file containing the list of hosts to backup."
    echo "-p <passphrase_file>   Path to the file containing the passphrase for encryption."
    echo "-k <ssh_key>           Path to the SSH key for connecting to the remote hosts."
    echo "-e <exclude_file>      Path to the file containing the list of files to exclude from the backup."
    echo "-b <backup_dir>        Path to the directory where the backups should be stored."
    echo "-l <log_file>          Path to the file where logs should be written."
    echo
    exit 1
}

# Set default variables
HOSTS_FILE="hosts.txt"
PASSPHRASE_FILE="passphrase.txt"
SSH_KEY="$HOME/.ssh/ssh_key"
EXCLUDE_FILE="exclude.txt"
BACKUP_DIR="backups"
LOG_FILE="backup.log"

# Check if at least one option is provided
if [ $# -eq 0 ]; then
    usage
fi

# Parse options
while getopts "h:p:k:e:b:l:" opt; do
    case ${opt} in
        h) HOSTS_FILE=$OPTARG ;;
        p) PASSPHRASE_FILE=$OPTARG ;;
        k) SSH_KEY=$OPTARG ;;
        e) EXCLUDE_FILE=$OPTARG ;;
        b) BACKUP_DIR=$OPTARG ;;
        l) LOG_FILE=$OPTARG ;;
        *) usage ;;
    esac
done

readonly TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"

log_error() {
    echo "$(date) [ERROR]: $1" | tee -a "$LOG_FILE"
}

validate_files() {
    local files=("$HOSTS_FILE" "$EXCLUDE_FILE" "$SSH_KEY" "$PASSPHRASE_FILE")
    for file in "${files[@]}"; do
        if [[ ! -r "$file" ]]; then
            log_error "Error: '$file' does not exist or is not readable."
            return 1
        fi
    done
}

backup_host() {
    local ssh_conn=$1
    local src_dir=$2
    local host_name
    host_name=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -n "$ssh_conn" hostname 2>/dev/null)

    # Check if ssh command was successful
    if [[ $? -ne 0 ]]; then
        log_error "SSH failed for $ssh_conn"
        return 1
    fi

    local backup_file="${host_name}_${TIMESTAMP}.tar.gz.gpg"

    if ! mkdir -p "${BACKUP_DIR}/${host_name}"; then
        log_error "Failed to create backup directory ${BACKUP_DIR}/${host_name}"
        return 1
    fi

    if ! rsync --timeout=10 -av --delete --exclude-from="$EXCLUDE_FILE" -e "ssh -i $SSH_KEY" "$ssh_conn:$src_dir" "${BACKUP_DIR}/${host_name}/"; then
        log_error "rsync failed for $ssh_conn:$src_dir"
        return 1
    fi

    if ! tar -czf - "${BACKUP_DIR}/${host_name}/" | gpg --batch --symmetric --passphrase "$PASSPHRASE" -o "${BACKUP_DIR}/${backup_file}"; then
        log_error "tar or gpg failed for $ssh_conn:$src_dir"
        return 1
    fi

    if ! rm -rf "${BACKUP_DIR}/${host_name}/"; then
        log_error "Failed to delete temporary backup directory ${BACKUP_DIR}/${host_name}/"
    fi

    echo "Backup of $ssh_conn:$src_dir completed and saved as ${BACKUP_DIR}/${backup_file}"
}

# Validate that all files exist and are readable
if ! validate_files; then
    exit 1
fi

# Read passphrase from file
PASSPHRASE=$(cat "$PASSPHRASE_FILE")
if [[ $? -ne 0 ]]; then
    log_error "Failed to read passphrase from $PASSPHRASE_FILE"
    exit 1
fi

# Loop through hosts in hosts.txt file
while read -r ssh_conn src_dir; do
    echo "Starting backup of $ssh_conn:$src_dir..."
    if backup_host "$ssh_conn" "$src_dir"; then
        echo "Backup of $ssh_conn:$src_dir completed successfully."
    else
        log_error "Backup failed for $ssh_conn:$src_dir"
        echo "Continuing with the next host..."
    fi
done < "$HOSTS_FILE"

# Restore instructions
echo ""
echo "To restore a backup, copy the encrypted backup file to the remote host and run the following command:"
echo "gpg --batch --decrypt --passphrase \"\$(cat passphrase.txt)\" <backup_file> | tar -xzf - -C /path/to/restore"
