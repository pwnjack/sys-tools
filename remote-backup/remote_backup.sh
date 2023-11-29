#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 -h <hosts_file> -p <passphrase_file> -k <ssh_key> -e <exclude_file> -b <backup_dir> -l <log_file> [-s]"
    echo
    echo "Options:"
    echo "-h <hosts_file>        Path to the file containing the list of hosts to backup."
    echo "-p <passphrase_file>   Path to the file containing the passphrase for encryption."
    echo "-k <ssh_key>           Path to the SSH key for connecting to the remote hosts."
    echo "-e <exclude_file>      Path to the file containing the list of files to exclude from the backup."
    echo "-b <backup_dir>        Path to the directory where the backups should be stored."
    echo "-l <log_file>          Path to the file where logs should be written."
    echo "-s                     Silent mode. Suppresses all output."
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
SILENT_MODE=0

# Check if at least one option is provided
if [ $# -eq 0 ]; then
    usage
fi

# Parse options
while getopts "h:p:k:e:b:l:s" opt; do
    case ${opt} in
        h) HOSTS_FILE=${OPTARG} ;;
        p) PASSPHRASE_FILE=${OPTARG} ;;
        k) SSH_KEY=${OPTARG} ;;
        e) EXCLUDE_FILE=${OPTARG} ;;
        b) BACKUP_DIR=${OPTARG} ;;
        l) LOG_FILE=${OPTARG} ;;
        s) SILENT_MODE=1 ;;
        *) usage ;;
    esac
done

# Function to log messages
log_message() {
    local message_type=$1
    local message=$2
    local timestamp=$(date)
    if [ ${SILENT_MODE} -eq 0 ]; then
        echo "${timestamp} [${message_type}]: ${message}" | tee -a "${LOG_FILE}"
    else
        echo "${timestamp} [${message_type}]: ${message}" >> "${LOG_FILE}"
    fi
}

# Function to validate file permissions
validate_permissions() {
    local file=$1
    local permissions
    permissions=$(stat -c "%a" "${file}")
    if [ "${permissions}" -gt "600" ]; then
        log_message "ERROR" "Permissions for ${file} are too open. It is recommended to use 'chmod 600 ${file}' to set proper permissions."
        exit 1
    fi
}

# Function to validate that all files exist and are readable
validate_files() {
    local files=("${HOSTS_FILE}" "${EXCLUDE_FILE}" "${SSH_KEY}" "${PASSPHRASE_FILE}")
    for file in "${files[@]}"; do
        if [[ ! -r "${file}" ]]; then
            log_message "ERROR" "Error: '${file}' does not exist or is not readable."
            return 1
        fi
        validate_permissions "${file}"
    done
}

# Function to backup a single host
backup_host() {
    local ssh_conn=$1
    local src_dir=$2
    local host_name
    host_name=$(ssh -i "${SSH_KEY}" -o ConnectTimeout=10 -n "${ssh_conn}" hostname 2>/dev/null)

    # Check if ssh command was successful
    if [[ $? -ne 0 ]]; then
        log_message "ERROR" "SSH failed for ${ssh_conn}"
        return 1
    else
        log_message "INFO" "Connected via SSH to ${host_name}"
    fi

    local backup_file="${host_name}_$(date +%Y-%m-%d_%H-%M-%S).tar.gz.gpg"

    if ! mkdir -p "${BACKUP_DIR}/${host_name}"; then
        log_message "ERROR" "Failed to create backup directory ${BACKUP_DIR}/${host_name}"
        return 1
    else
        log_message "INFO" "Created backup directory"
    fi

    if ! rsync --timeout=10 -av --delete --exclude-from="${EXCLUDE_FILE}" -e "ssh -i ${SSH_KEY}" "${ssh_conn}:${src_dir}" "${BACKUP_DIR}/${host_name}/"; then
        log_message "ERROR" "rsync failed for ${ssh_conn}:${src_dir}"
        return 1
    else
        log_message "INFO" "rsync completed for ${ssh_conn}:${src_dir}"
    fi

    local passphrase
    passphrase=$(<"${PASSPHRASE_FILE}")

    # Ensure the backup directory is cleaned up on script exit or error
    trap 'rm -rf "${BACKUP_DIR:?}/${host_name}"' EXIT

    if ! tar -czf - "${BACKUP_DIR}/${host_name}/" | gpg --batch --symmetric --passphrase "${passphrase}" -o "${BACKUP_DIR}/${backup_file}"; then
        log_message "ERROR" "Backup encryption failed for ${host_name}"
        return 1
    else
        log_message "INFO" "Backup encryption completed for ${host_name}"
    fi

    # Clean up the unencrypted backup directory
    rm -rf "${BACKUP_DIR}/${host_name}"
    log_message "INFO" "Cleaned up backup directory for ${host_name}"
}

# Validate that all required files exist and are readable
validate_files || exit 1

# Read hosts file and start the backup process
while IFS= read -r line || [[ -n "$line" ]]; do
    backup_host ${line}
done < "${HOSTS_FILE}"

# Check if the read command succeeded
if [ $? -ne 0 ]; then
    log_message "ERROR" "Failed to read from ${HOSTS_FILE}"
    exit 1
fi

log_message "INFO" "Backup script completed"