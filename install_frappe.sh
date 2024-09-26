#!/usr/bin/env bash

# Frappe V15 & ERPNext Quick Install Script
# This script installs Frappe Framework and ERPNext version 15 on Ubuntu 22.04 or 24.04 within WSL.
# It ensures all dependencies are installed, configures MariaDB 10.6, creates a dedicated 'frappe' user,
# and sets up the necessary environment for Frappe and ERPNext to run smoothly.

# Exit immediately if a command exits with a non-zero status.
set -e

# Define color codes for output
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
LIGHT_BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Function to handle errors
handle_error() {
    local line="$1"
    local exit_code="$2"
    echo -e "\n${RED}Error: An error occurred on line ${line} with exit code ${exit_code}.${NC}"
    exit "$exit_code"
}

# Trap errors and call handle_error
trap 'handle_error ${LINENO} $?' ERR

# Function to check OS compatibility
check_os() {
    local os_name
    local os_version
    os_name=$(lsb_release -is)
    os_version=$(lsb_release -rs)

    if [[ "$os_name" != "Ubuntu" ]]; then
        echo -e "${RED}Unsupported Operating System: $os_name. Only Ubuntu is supported.${NC}"
        exit 1
    fi

    if [[ ! " ${SUPPORTED_VERSIONS[@]} " =~ " ${os_version} " ]]; then
        echo -e "${RED}Unsupported Ubuntu version: $os_version. Supported versions are: ${SUPPORTED_VERSIONS[*]}.${NC}"
        exit 1
    fi
}

SUPPORTED_VERSIONS=("22.04" "24.04")

check_os

# Function to prompt user for password confirmation
ask_twice() {
    local prompt="$1"
    local secret="$2"
    local val1 val2

    while true; do
        if [ "$secret" = "true" ]; then
            read -rsp "$prompt: " val1
            echo
        else
            read -rp "$prompt: " val1
        fi

        if [ "$secret" = "true" ]; then
            read -rsp "Confirm password: " val2
            echo
        else
            read -rp "Confirm input: " val2
        fi

        if [ "$val1" = "$val2" ]; then
            echo -e "${GREEN}Input confirmed.${NC}"
            echo "$val1"
            break
        else
            echo -e "${RED}Inputs do not match. Please try again.${NC}"
        fi
    done
}

echo -e "${LIGHT_BLUE}Welcome to the Frappe V15 & ERPNext Quick Install Script...${NC}"
sleep 2

# Prompt for MariaDB root password
echo -e "${YELLOW}Setting up MariaDB root password...${NC}"
sqlpasswrd=$(ask_twice "Enter your MariaDB root password" "true")
echo

# Function to check if a package is installed
is_installed() {
    dpkg -s "$1" &>/dev/null
}

# Function to uninstall MariaDB if installed and not version 10.6
uninstall_mariadb() {
    if is_installed mariadb-server || is_installed mariadb-client; then
        installed_version=$(mariadb --version | awk '{print $5}' | cut -d',' -f1)
        if [[ "$installed_version" != "10.6."* ]]; then
            echo -e "${YELLOW}Removing existing MariaDB installation (Version: $installed_version)...${NC}"
            sudo systemctl stop mariadb || true
            sudo apt-get remove --purge -y mariadb-server mariadb-client mariadb-common
            sudo apt-get autoremove -y
            sudo apt-get autoclean
            sudo rm -rf /etc/mysql /var/lib/mysql
            echo -e "${GREEN}Existing MariaDB installation removed.${NC}"
        else
            echo -e "${GREEN}MariaDB 10.6 is already installed.${NC}"
        fi
    else
        echo -e "${GREEN}No existing MariaDB installation found.${NC}"
    fi
}

# Function to install MariaDB 10.6
install_mariadb() {
    echo -e "${YELLOW}Installing MariaDB 10.6...${NC}"
    
    # Determine Ubuntu codename
    ubuntu_codename=$(lsb_release -cs)
    
    # Install software-properties-common and dirmngr
    sudo apt install -y software-properties-common dirmngr
    
    # Import MariaDB GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://mariadb.org/mariadb_release_signing_key.asc | sudo gpg --dearmor -o /etc/apt/keyrings/mariadb-keyring.gpg
    
    # Add MariaDB repository
    echo "deb [arch=amd64,arm64,ppc64el signed-by=/etc/apt/keyrings/mariadb-keyring.gpg] https://mariadb.org/mariadb/repositories/10.6/ubuntu ${ubuntu_codename} main" | sudo tee /etc/apt/sources.list.d/mariadb.list
    
    # Update package lists
    sudo apt update
    
    # Install MariaDB 10.6
    sudo apt install -y mariadb-server mariadb-client
    
    # Verify MariaDB version
    installed_mariadb_version=$(mariadb --version | awk '{print $5}' | cut -d',' -f1)
    if [[ "$installed_mariadb_version" != "10.6."* ]]; then
        echo -e "${RED}MariaDB 10.6 installation failed. Installed version: $installed_mariadb_version${NC}"
        exit 1
    fi
    echo -e "${GREEN}MariaDB 10.6 installed successfully.${NC}"
    sleep 2
}

# Function to configure MariaDB
configure_mariadb() {
    echo -e "${YELLOW}Updating MariaDB configuration...${NC}"
    sleep 2

    # Backup the original configuration file if not already backed up
    if [ ! -f /etc/mysql/mariadb.conf.d/50-server.cnf.bak ]; then
        sudo cp /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf.bak
        echo -e "${GREEN}Original MariaDB configuration file backed up.${NC}"
    else
        echo -e "${GREEN}Backup of MariaDB configuration file already exists.${NC}"
    fi

    # Overwrite the configuration file
    sudo tee /etc/mysql/mariadb.conf.d/50-server.cnf > /dev/null <<EOF
# These groups are read by MariaDB server.
# Use it for options that only the server (but not clients) should see
# this is read by the standalone daemon and embedded servers
[server]

# this is only for the mysqld standalone daemon
[mysqld]

#
# * Basic Settings
#
user                    = mysql
pid-file                = /run/mysqld/mysqld.pid
basedir                 = /usr
datadir                 = /var/lib/mysql
tmpdir                  = /tmp
# Broken reverse DNS slows down connections considerably and name resolve is
# safe to skip if there are no "host by domain name" access grants
skip-name-resolve
# Instead of skip-networking the default is now to listen only on
# localhost which is more compatible and is not less secure.
bind-address            = 127.0.0.1

#
# * Fine Tuning
#
key_buffer_size        = 128M
max_allowed_packet     = 1G
thread_stack           = 192K
thread_cache_size      = 8
# This replaces the startup script and checks MyISAM tables if needed
# the first time they are touched
myisam_recover_options = BACKUP
max_connections        = 100
table_cache            = 64

#
# * Logging and Replication
#
# Both location gets rotated by the cronjob.
# Be aware that this log type is a performance killer.
# Recommend only changing this at runtime for short testing periods if needed!
#general_log_file       = /var/log/mysql/mysql.log
#general_log            = 1

# When running under systemd, error logging goes via stdout/stderr to journald
# and when running legacy init error logging goes to syslog due to
# /etc/mysql/conf.d/mariadb.conf.d/50-mysqld_safe.cnf
# Enable this if you want to have error logging into a separate file
#log_error = /var/log/mysql/error.log

# Enable the slow query log to see queries with especially long duration
#slow_query_log_file    = /var/log/mysql/mariadb-slow.log
#long_query_time        = 10
#log_slow_verbosity     = query_plan,explain
#log-queries-not-using-indexes
#min_examined_row_limit = 1000

# The following can be used as easy to replay backup logs or for replication.
# note: if you are setting up a replication slave, see README.Debian about
#       other settings you may need to change.
#server-id              = 1
#log_bin                = /var/log/mysql/mysql-bin.log
expire_logs_days        = 10
#max_binlog_size        = 100M

#
# * SSL/TLS
#
# For documentation, please read
# https://mariadb.com/kb/en/securing-connections-for-client-and-server/
#ssl-ca = /etc/mysql/cacert.pem
#ssl-cert = /etc/mysql/server-cert.pem
#ssl-key = /etc/mysql/server-key.pem
#require-secure-transport = on

#
# * Character sets
#
# MySQL/MariaDB default is Latin1, but in Debian we rather default to the full
# utf8 4-byte character set. See also client.cnf
character-set-server  = utf8mb4
collation-server      = utf8mb4_general_ci

#
# * InnoDB
#
# InnoDB is enabled by default with a 10MB datafile in /var/lib/mysql/.
# Read the manual for more InnoDB related options. There are many!
# Most important is to give InnoDB 80 % of the system RAM for buffer use:
# https://mariadb.com/kb/en/innodb-system-variables/#innodb_buffer_pool_size
#innodb_buffer_pool_size = 8G

# this is only for embedded server
[embedded]

# This group is only read by MariaDB servers, not by MySQL.
# If you use the same .cnf file for MySQL and MariaDB,
# you can put MariaDB-only options here
[mariadb]

# This group is only read by MariaDB-10.6 servers.
# If you use the same .cnf file for MariaDB of different versions,
# use this group for options that older servers don't understand
[mariadb-10.6]
EOF

    # Restart MariaDB to apply new configuration
    echo -e "${YELLOW}Restarting MariaDB to apply new configuration...${NC}"
    sudo systemctl restart mariadb

    # MariaDB Security Configuration
    echo -e "${YELLOW}Applying MariaDB security settings...${NC}"
    sleep 2

    # Apply the security settings
    password_changed=false
    while [ "$password_changed" = false ]; do
        sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$sqlpasswrd';"

        # Check if the password update was successful
        if sudo mysql -u root -p"$sqlpasswrd" -e "SELECT 1;" &> /dev/null; then
            password_changed=true
            echo -e "${GREEN}Password update successful!${NC}"
        else
            echo -e "${RED}Password update failed! Retrying...${NC}"
            sleep 2 # wait for 2 seconds before retrying
        fi
    done

    # Grant privileges to root user for localhost and 127.0.0.1
    sudo mysql -u root -p"$sqlpasswrd" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' IDENTIFIED BY '$sqlpasswrd' WITH GRANT OPTION;"
    sudo mysql -u root -p"$sqlpasswrd" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' IDENTIFIED BY '$sqlpasswrd' WITH GRANT OPTION;"
    sudo mysql -u root -p"$sqlpasswrd" -e "FLUSH PRIVILEGES;"

    # Remove anonymous users and test database
    sudo mysql -u root -p"$sqlpasswrd" -e "DELETE FROM mysql.user WHERE User='';"
    sudo mysql -u root -p"$sqlpasswrd" -e "DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    sudo mysql -u root -p"$sqlpasswrd" -e "FLUSH PRIVILEGES;"

    echo -e "${GREEN}MariaDB configuration and security settings completed!${NC}"
    echo -e "\n"
    sleep 1
}

# Function to install Python 3.10 if necessary
install_python() {
    PYTHON_VERSION_REQUIRED="3.10"
    current_python_version=$(python3 --version 2>/dev/null | awk '{print $2}')

    if [[ -z "$current_python_version" || "$(printf '%s\n' "$PYTHON_VERSION_REQUIRED" "$current_python_version" | sort -V | head -n1)" != "$PYTHON_VERSION_REQUIRED" ]]; then
        echo -e "${YELLOW}Installing Python ${PYTHON_VERSION_REQUIRED}...${NC}"
        sleep 2

        sudo apt install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
            libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev

        wget https://www.python.org/ftp/python/3.10.11/Python-3.10.11.tgz
        tar -xf Python-3.10.11.tgz
        cd Python-3.10.11
        ./configure --enable-optimizations --enable-shared
        make -j "$(nproc)"
        sudo make altinstall
        cd ..
        rm -rf Python-3.10.11 Python-3.10.11.tgz

        # Update alternatives
        sudo update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.10 1

        echo -e "${GREEN}Python ${PYTHON_VERSION_REQUIRED} installed successfully.${NC}"
        sleep 2
    else
        echo -e "${GREEN}Python ${PYTHON_VERSION_REQUIRED} is already installed.${NC}"
    fi
}

# Function to install NVM, Node.js, npm, and yarn
install_node_npm_yarn() {
    echo -e "${YELLOW}Installing NVM, Node.js, npm, and yarn...${NC}"
    sleep 2
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash

    # Load NVM into the current shell
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # Install Node.js version 18 for Frappe version 15
    echo -e "${YELLOW}Installing Node.js version 18...${NC}"
    nvm install 18
    nvm use 18
    nvm alias default 18

    sudo apt-get install -y npm
    sudo npm install -g yarn
    echo -e "${GREEN}NVM, Node.js, npm, and yarn installed.${NC}"
    sleep 2
}

# Function to install Bench CLI
install_bench() {
    echo -e "${YELLOW}Installing Bench CLI...${NC}"
    sudo pip3 install frappe-bench
    echo -e "${GREEN}Bench CLI installed.${NC}"
    sleep 2
}

# Function to initialize Bench
initialize_bench() {
    echo -e "${YELLOW}Initializing Bench in frappe-bench directory...${NC}"
    bench init frappe-bench --frappe-branch version-15 --verbose
    echo -e "${GREEN}Bench initialized.${NC}"
    sleep 2
}

# Function to create a new site
create_site() {
    echo -e "${YELLOW}Preparing to create a new site. This may take a few minutes...${NC}"
    read -rp "Enter the site name (use FQDN if you plan to install SSL): " site_name
    adminpasswrd=$(ask_twice "Enter the Administrator password" "true")
    echo

    # Create new site
    echo -e "${YELLOW}Creating new site: ${site_name}...${NC}"
    cd frappe-bench
    bench new-site "$site_name" --db-root-password "$sqlpasswrd" --admin-password "$adminpasswrd"
    echo -e "${GREEN}Site created successfully.${NC}"
    sleep 2
}

# Function to install ERPNext optionally
install_erpnext() {
    echo -e "${LIGHT_BLUE}Would you like to install ERPNext? (yes/no)${NC}"
    read -rp "Response: " erpnext_install
    erpnext_install=$(echo "$erpnext_install" | tr '[:upper:]' '[:lower:]')

    while [[ "$erpnext_install" != "yes" && "$erpnext_install" != "y" && "$erpnext_install" != "no" && "$erpnext_install" != "n" ]]; do
        echo -e "${RED}Invalid response. Please answer with 'yes' or 'no'.${NC}"
        echo -e "${LIGHT_BLUE}Would you like to install ERPNext? (yes/no)${NC}"
        read -rp "Response: " erpnext_install
        erpnext_install=$(echo "$erpnext_install" | tr '[:upper:]' '[:lower:]')
    done

    if [[ "$erpnext_install" == "yes" || "$erpnext_install" == "y" ]]; then
        echo -e "${YELLOW}Installing ERPNext...${NC}"
        bench get-app erpnext --branch version-15
        bench --site "$site_name" install-app erpnext
        echo -e "${GREEN}ERPNext installed successfully.${NC}"
        sleep 2
    else
        echo -e "${RED}Skipping ERPNext installation.${NC}"
        sleep 2
    fi
}

# Function to setup production
setup_production() {
    echo -e "${YELLOW}Setting up production environment...${NC}"
    bench setup production "$USER"
    echo -e "${GREEN}Production environment set up successfully.${NC}"
    sleep 2
}

# Function to install SSL optionally
install_ssl() {
    echo -e "${YELLOW}Would you like to install SSL? (yes/no)${NC}"
    read -rp "Response: " install_ssl
    install_ssl=$(echo "$install_ssl" | tr '[:upper:]' '[:lower:]')

    while [[ "$install_ssl" != "yes" && "$install_ssl" != "y" && "$install_ssl" != "no" && "$install_ssl" != "n" ]]; do
        echo -e "${RED}Invalid response. Please answer with 'yes' or 'no'.${NC}"
        echo -e "${YELLOW}Would you like to install SSL? (yes/no)${NC}"
        read -rp "Response: " install_ssl
        install_ssl=$(echo "$install_ssl" | tr '[:upper:]' '[:lower:]')
    done

    if [[ "$install_ssl" == "yes" || "$install_ssl" == "y" ]]; then
        echo -e "${YELLOW}Installing Certbot for SSL...${NC}"
        sudo apt install -y snapd
        sudo snap install core
        sudo snap refresh core
        sudo snap install --classic certbot
        sudo ln -s /snap/bin/certbot /usr/bin/certbot

        echo -e "${YELLOW}Obtaining and installing SSL certificate...${NC}"
        read -rp "Enter your email address for SSL certificate: " email_address

        # Ensure domain points to server before proceeding
        echo -e "${YELLOW}Ensure your domain name is pointed to this server's IP address before proceeding.${NC}"
        echo -e "${YELLOW}Press Enter to continue..."
        read

        sudo certbot --nginx --non-interactive --agree-tos --email "$email_address" -d "$site_name"
        echo -e "${GREEN}SSL certificate installed successfully.${NC}"
        sleep 2
    else
        echo -e "${RED}Skipping SSL installation.${NC}"
        sleep 2
    fi
}

# Function to apply final permissions
apply_permissions() {
    echo -e "${YELLOW}Applying final permissions...${NC}"
    sudo chmod -R 755 "$HOME/frappe-bench"
    echo -e "${GREEN}Permissions applied.${NC}"
    sleep 2
}

# Function to create a dedicated frappe user
create_frappe_user() {
    if id "frappe" &>/dev/null; then
        echo -e "${GREEN}User 'frappe' already exists.${NC}"
    else
        echo -e "${YELLOW}Creating 'frappe' user...${NC}"
        sudo adduser --disabled-password --gecos "" frappe
        echo -e "${GREEN}'frappe' user created successfully.${NC}"
    fi

    # Grant frappe user sudo privileges if not already granted
    if sudo grep -q "^frappe ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/frappe 2>/dev/null; then
        echo -e "${GREEN}'frappe' user already has sudo privileges.${NC}"
    else
        echo -e "${YELLOW}Granting 'frappe' user sudo privileges...${NC}"
        echo "frappe ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/frappe
        sudo chmod 0440 /etc/sudoers.d/frappe
        echo -e "${GREEN}'frappe' user granted sudo privileges.${NC}"
    fi
}

# Function to switch to frappe user and run Bench commands
run_as_frappe() {
    sudo -u frappe bash -c "
        # Navigate to home directory
        cd \$HOME

        # Clone the installer repository if it doesn't exist
        if [ -d 'Frappe-V15---ERP-Next-Quick-Install' ]; then
            echo 'Repository already cloned.'
        else
            echo 'Cloning the installer repository...'
            git clone https://github.com/kamikazce/Frappe-V15---ERP-Next-Quick-Install.git
            echo 'Repository cloned successfully.'
        fi

        # Navigate to the installer directory
        cd Frappe-V15---ERP-Next-Quick-Install

        # Make the installer script executable
        chmod +x install_frappe.sh

        # Run the installer script
        ./install_frappe.sh
    "
}

# Main Installation Flow

echo -e "${YELLOW}Now setting up your environment...${NC}"
sleep 2

# Create frappe user
create_frappe_user

# Install essential packages and dependencies
echo -e "${YELLOW}Installing essential packages and dependencies...${NC}"
sleep 2
sudo apt update && sudo apt upgrade -y

sudo apt install -y software-properties-common git curl wget gnupg build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
    libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev libbz2-dev python3-dev python3-venv python3-pip \
    redis-server mariadb-server mariadb-client snapd fontconfig libxrender1 xfonts-75dpi xfonts-base

# Install wkhtmltopdf
echo -e "${YELLOW}Installing wkhtmltopdf...${NC}"
sleep 2
arch=$(uname -m)
case $arch in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *) echo -e "${RED}Unsupported architecture: $arch${NC}"; exit 1 ;;
esac

wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_$arch.deb
sudo dpkg -i wkhtmltox_0.12.6.1-2.jammy_$arch.deb || true
sudo cp /usr/local/bin/wkhtmlto* /usr/bin/
sudo chmod a+x /usr/bin/wk*
sudo rm wkhtmltox_0.12.6.1-2.jammy_$arch.deb
sudo apt --fix-broken install -y
sudo apt install -y fontconfig xvfb libfontconfig xfonts-base xfonts-75dpi libxrender1
echo -e "${GREEN}wkhtmltopdf installed successfully.${NC}"
sleep 2

# Uninstall existing MariaDB if necessary
uninstall_mariadb

# Install MariaDB 10.6
install_mariadb

# Configure MariaDB
configure_mariadb

# Install Python 3.10 if necessary
install_python

# Install NVM, Node.js, npm, and yarn
install_node_npm_yarn

# Install Bench CLI
install_bench

# Initialize Bench
initialize_bench

# Create a new site
create_site

# Install ERPNext optionally
install_erpnext

# Setup production environment
setup_production

# Install SSL optionally
install_ssl

# Apply final permissions
apply_permissions

# Completion message
echo -e "${GREEN}--------------------------------------------------------------------------------"
if [[ "$install_ssl" == "yes" || "$install_ssl" == "y" ]]; then
    echo -e "Congratulations! You have successfully installed Frappe and ERPNext version 15 with SSL."
    echo -e "You can access your ERPNext instance securely at https://$site_name"
else
    server_ip=$(hostname -I | awk '{print $1}')
    echo -e "Congratulations! You have successfully installed Frappe and ERPNext version 15."
    echo -e "You can access your ERPNext instance at http://$server_ip"
fi
echo -e "Visit https://docs.erpnext.com for documentation."
echo -e "Enjoy using ERPNext!"
echo -e "--------------------------------------------------------------------------------${NC}"

