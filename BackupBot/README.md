# Remote Backup Script

## Description

This script is designed to perform automated backups of remote hosts using Rsync and GPG encryption. It allows you to securely back up specified directories on multiple hosts, store the encrypted backups locally, and maintain a local copy of the last backup state for efficient future backups.

## Prerequisites

Before using this script, ensure you have the following:

- Bash shell environment
- SSH key for remote authentication
- A passphrase for encryption
- Rsync installed on the local system
- MSMTP installed on the local system (to send e-mail alerts on backup failures)

## Usage

    ./backupbot.sh -h <hosts_file> -p <passphrase_file> -k <ssh_key> -e <exclude_file> -b <backup_dir> -t <temp_dir> -l <log_file> [-s] [-v]

## Options

    -h <hosts_file>: Path to the file containing the list of hosts and directories to back up.
    -p <passphrase_file>: Path to the file containing the passphrase for encryption.
    -k <ssh_key>: Path to the SSH key for connecting to the remote hosts.
    -e <exclude_file>: Path to the file containing the list of files to exclude from the backup.
    -b <backup_dir>: Path to the directory where the backups should be stored.
    -t <temp_dir>: Path to the directory for storing temporary incremental backup data.
    -l <log_file>: Path to the file where logs should be written.
    -s: Silent mode. Suppresses all output to stdout.
    -v: Verbose mode. Outputs detailed information about the backup process.

## Example files

Example of `hosts.txt` file:

    user1@host1 /path/to/dir1
    user2@host2 /path/to/dir2

Example of `exclude.txt` file:

    *.log
    .cache/
    tmp/

## Example Usage

    ./backupbot.sh -h hosts.txt -p passphrase.txt -k ~/.ssh/id_rsa -e exclude.txt -b backups -t tmp -l backup.log

## Execution

If you don't specify any options, the script will display the usage information. Providing at least one option will execute the script using the default settings for any options that weren't specified. The script processes the provided options, checks that all required files exist and are readable, retrieves the passphrase from the file, and starts the backup process for each host and directory listed in the `hosts.txt` file.

## Default Variables

The script uses the following default variables, which can be overridden by command-line options:

    HOSTS_FILE: hosts.txt
    PASSPHRASE_FILE: passphrase.txt
    SSH_KEY: ~/.ssh/id_rsa
    EXCLUDE_FILE: exclude.txt
    BACKUP_DIR: backups
    TEMP_DIR: tmp
    LOG_FILE: backup.log

These defaults are set in the `backup.conf` configuration file.

## Restoring a Backup

To restore a backup, copy the encrypted backup file to the remote host and run the following command:

    gpg --batch --decrypt --passphrase "$(cat passphrase.txt)" <backup_file> | tar -xzf - -C /path/to/restore

## Note

Ensure the passphrase file `passphrase.txt` is kept secure and not shared with unauthorized users.
Always store backups in a secure location. The temporary directory for incremental backups should be secured and not accessible by unauthorized users.

## License and Authorship

Author: @pwnjack

This script is provided under the MIT License.
