# Remote Backup Script

## Description

This script is designed to perform automated backups of remote hosts using Rsync, and GPG encryption. It allows you to securely back up specified directories on multiple hosts and store the encrypted backups locally.

## Prerequisites

Before using this script, ensure you have the following:

- Bash shell environment
- SSH key for remote authentication
- A passphrase for encryption
- Rsync installed on the local system

## Usage

    ./backup_script.sh -h <hosts_file> -p <passphrase_file> -k <ssh_key> -e <exclude_file> -b <backup_dir> -l <log_file>

## Options

    -h <hosts_file>: Path to the file containing the list of hosts and directories to back up.
    -p <passphrase_file>: Path to the file containing the passphrase for encryption.
    -k <ssh_key>: Path to the SSH key for connecting to the remote hosts.
    -e <exclude_file>: Path to the file containing the list of files to exclude from the backup.
    -b <backup_dir>: Path to the directory where the backups should be stored.
    -l <log_file>: Path to the file where logs should be written.

## Example files

Example of `hosts.txt` file:

    user1@host1 /path/to/dir1
    user2@host2 /path/to/dir2

Example of `exclude.txt` file:

    *.log
    .cache/
    tmp/

## Example Usage

    ./backup_script.sh -h hosts.txt -p passphrase.txt -k ~/.ssh/ssh_key -e exclude.txt -b backups -l backup.log

## Execution

If you don't specify any options, the script will just display the usage. But if you provide at least one option, it will execute using default settings for any that weren't specified. It will then process the provided options, checking that all required files exist and are readable. Next, it will retrieve the passphrase from the file. Finally, it will start the backup process for each host and directory listed in `hosts.txt`

## Default Variables

    HOSTS_FILE: hosts.txt
    PASSPHRASE_FILE: passphrase.txt
    SSH_KEY: ~/.ssh/ssh_key
    EXCLUDE_FILE: exclude.txt
    BACKUP_DIR: backups
    LOG_FILE: backup.log

## Restoring a Backup

To restore a backup, copy the encrypted backup file to the remote host and run the following command:

    gpg --batch --decrypt --passphrase "$(cat passphrase.txt)" <backup_file> | tar -xzf - -C /path/to/restore

## Note

Ensure the passphrase file `passphrase.txt` is kept secure and not shared with unauthorized users.
Always store backups in a secure location.

## License

This script is provided under the MIT License.
