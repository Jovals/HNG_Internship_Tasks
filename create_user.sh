#!/bin/bash

# Log file and password file creation
LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE="/var/secure/user_passwords.txt"

# Ensure script is run as root/sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or use sudo."
    exit 1
fi

# Create directories and files if they don't exist, and set permissions
mkdir -p /var/log
mkdir -p /var/secure
touch $LOG_FILE
touch $PASSWORD_FILE
chmod 600 $PASSWORD_FILE

# Function to create log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# Function to generate a random password
generate_password() {
    echo $(openssl rand -base64 12)
}

# Check if the input file is provided
if [ -z "$1" ]; then
    echo "Usage: sudo bash $0 <name-of-text-file>"
    exit 1
fi

# Read the input file
INPUT_FILE=$1

# Process each line in the input file
while IFS=';' read -r username groups; do
    # Ignore empty lines and lines that start with a hash (#)
    if [[ -z "$username" || "$username" == \#* ]]; then
        continue
    fi

    # Removing all whitespace from username and groups
    username=$(echo "$username" | xargs)
    groups=$(echo "$groups" | xargs)

    # Check if user already exists
    if id "$username" &>/dev/null; then
        log_message "User '$username' already exists."
    else
        # Create user with home directory and bash shell
        useradd -m -s /bin/bash "$username"
        if [ $? -eq 0 ]; then
            log_message "Created user '$username'."
        else
            log_message "Failed to create user '$username'."
            continue
        fi

        # Create personal group with the same name as the user
        usermod -g "$username" "$username"
        if [ $? -eq 0 ]; then
            log_message "Created personal group for user '$username'."
        else
            log_message "Failed to create personal group for user '$username'."
        fi
        
        # Generate and set a random password for the user
        password=$(generate_password)
        echo "$username:$password" | chpasswd
        if [ $? -eq 0 ]; then
            log_message "Set password for user '$username'."
        else
            log_message "Failed to set password for user '$username'."
        fi
        
        # Save the password to the secure file
        echo "$username,$password" >> $PASSWORD_FILE
    fi

    # Add user to specified groups if there are any
    if [ -n "$groups" ]; then
        # Split groups by comma and loop through each group
        IFS=',' read -r groups_list <<< "$groups"
        for group in ${groups_list//,/ }; do
            group=$(echo "$group" | xargs) # Trim whitespace
            if getent group "$group" &>/dev/null; then
                usermod -aG "$group" "$username"
                if [ $? -eq 0 ]; then
                    log_message "Added user '$username' to group '$group'."
                else
                    log_message "Failed to add user '$username' to group '$group'."
                fi
            else
                groupadd "$group"
                if [ $? -eq 0 ]; then
                    usermod -aG "$group" "$username"
                    log_message "Created and added user '$username' to group '$group'."
                else
                    log_message "Failed to create group '$group' or add user '$username' to group."
                fi
            fi
        done
    fi

done < "$INPUT_FILE"

log_message "User creation and group assignment completed."
