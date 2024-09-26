#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Error handler to catch and report errors
handle_error() {
    local line="$1"
    local exit_code="$2"
    echo -e "\n${RED}An error occurred on line ${line} with exit status ${exit_code}.${NC}"
    exit "$exit_code"
}

trap 'handle_error ${LINENO} $?' ERR

# Define color codes for output
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
LIGHT_BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Supported OS and versions
SUPPORTED_OS="Ubuntu"
SUPPORTED_VERSIONS=("22.04" "24.04")

# Function to check OS compatibility
check_os() {
    local os_name
    local os_version
    os_name=$(lsb_release -is)
    os_version=$(lsb_release -rs)

    if [[ "$os_name" != "$SUPPORTED_OS" ]]; then
        echo -e "${RED}Unsupported Operating System: $os_name. Only Ubuntu is supported.${NC}"
        exit 1
    fi

    if [[ ! " ${SUPPORTED_VERSIONS[@]} " =~ " ${os_version} " ]]; then
        echo -e "${RED}Unsupported Ubuntu version: $os_version. Supported versions are: ${SUPPORTED_VERSIONS[*]}.${NC}"
        exit 1
    fi
}

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

echo -e "${LIGHT_BLUE}Welcome to the Frappe/ERPNext Installer...${NC}"
sleep 2

# Navigate to the home directory
cd "$HOME"

# Prompt for SQL root password
echo -e "${YELLOW}Setting up MariaDB root password...${NC}"
sqlpasswrd=$(ask_twice "Enter your MariaDB root password" "true")

# Update system packages
echo -e "${YELLOW}Updating system packages...${NC}"
sudo apt update && sudo apt upgrade -y
echo -e "${GREEN}System packages updated.${NC}"
sleep 2

# Install essential packages
echo -e "${YELLOW}Installing essential packages: git, curl, software-properties-common, wget, gnupg...${NC}"
sudo apt install -y software-properties-common git curl wget gnupg
echo -e "${GREEN}Essential packages installed.${NC}"
sleep 2

# Install Python 3.10 if not already installed
PYTHON_VERSION_REQUIRED="3.10"
current_python_version=$(python3 --version | awk '{print $2}')

if [[ "$(printf '%s\n' "$PYTHON_VERSION_REQUIRED" "$current_python_version" | sort -V | head -n1)" != "$PYTHON_VERSION_REQUIRED" ]]; then
    echo -e "${YELLOW}Installing Python ${PYTHON_VERSION_REQUIRED}...${NC}"
    sudo apt install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
        libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev

    wget https://www.python.org/ftp/python/3.10.11/Python-3.10.11.tgz
    tar -xf Python-3.10.11.tgz
    cd Python-3.10.11
    ./configure --enable-optimizations
    make -j "$(nproc)"
    sudo make altinstall
    cd ..
    rm -rf Python-3.10.11 Python-3.10.11.tgz

    # Update alternatives
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.10 1

    echo -e "${GREEN}Python ${PYTHON_VERSION_REQUIRED} installed successfully.${NC}"
    sleep 2
fi

# Install additional Python packages and Redis
echo -e "${YELLOW}Installing additional Python packages and Redis Server...${NC}"
sudo apt install -y python3-dev python3-venv python3-pip redis-server
echo -e "${GREEN}Python packages and Redis installed.${NC}"
sleep 2

# Install MariaDB 10.6
echo -e "${YELLOW}Installing MariaDB 10.6...${NC}"

# Add MariaDB repository
sudo apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
sudo add-apt-repository 'deb [arch=amd64,arm64,ppc64el] https://mariadb.org/mariadb/repositories/10.6/ubuntu focal main'

# Update and install MariaDB
sudo apt update
sudo apt install -y mariadb-server=1:10.6.12-0ubuntu0.20.04.1 mariadb-client=1:10.6.12-0ubuntu0.20.04.1

# Verify MariaDB version
installed_mariadb_version=$(mariadb --version | awk '{print $5}' | cut -d',' -f1)
if [[ "$installed_mariadb_version" != "10.6."* ]]; then
    echo -e "${RED}MariaDB 10.6 installation failed. Installed version: $installed_mariadb_version${NC}"
    exit 1
fi
echo -e "${GREEN}MariaDB 10.6 installed successfully.${NC}"
sleep 2

# MariaDB Configuration
echo -e "${YELLOW}Updating MariaDB configuration...${NC}"
sleep 2

# Backup the original configuration file
sudo cp /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf.bak

# Delete all content and insert new content
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

sudo mysql -u root -p"$sqlpasswrd" -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -u root -p"$sqlpasswrd" -e "DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
sudo mysql -u root -p"$sqlpasswrd" -e "FLUSH PRIVILEGES;"

echo -e "${GREEN}MariaDB configuration and security settings completed!${NC}"
echo -e "\n"
sleep 1

# Install NVM, Node.js, npm, and yarn
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

# Install Bench CLI
echo -e "${YELLOW}Installing Bench CLI...${NC}"
sudo pip3 install frappe-bench
echo -e "${GREEN}Bench CLI installed.${NC}"
sleep 2

# Initialize Bench
echo -e "${YELLOW}Initializing Bench in frappe-bench directory...${NC}"
bench init frappe-bench --frappe-branch version-15 --verbose
echo -e "${GREEN}Bench initialized.${NC}"
sleep 2

# Prompt for site name
echo -e "${YELLOW}Preparing to create a new site. This may take a few minutes...${NC}"
read -rp "Enter the site name (use FQDN if you plan to install SSL): " site_name
adminpasswrd=$(ask_twice "Enter the Administrator password" "true")

# Create new site
echo -e "${YELLOW}Creating new site: ${site_name}...${NC}"
cd frappe-bench
bench new-site "$site_name" --db-root-password "$sqlpasswrd" --admin-password "$adminpasswrd"
echo -e "${GREEN}Site created successfully.${NC}"
sleep 2

# Prompt to install ERPNext
echo -e "${LIGHT_BLUE}Would you like to install ERPNext? (yes/no)${NC}"
read -rp "Response: " erpnext_install
erpnext_install=$(echo "$erpnext_install" | tr '[:upper:]' '[:lower:]')

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

# Configure Supervisor and Nginx for Production
echo -e "${YELLOW}Setting up production environment...${NC}"
bench setup production "$USER"
echo -e "${GREEN}Production environment set up successfully.${NC}"
sleep 2

# Prompt to install SSL
echo -e "${YELLOW}Would you like to install SSL? (yes/no)${NC}"
read -rp "Response: " install_ssl
install_ssl=$(echo "$install_ssl" | tr '[:upper:]' '[:lower:]')

if [[ "$install_ssl" == "yes" || "$install_ssl" == "y" ]]; then
    echo -e "${YELLOW}Installing Certbot for SSL...${NC}"
    sudo apt install -y snapd
    sudo snap install core
    sudo snap refresh core
    sudo snap install --classic certbot
    sudo ln -s /snap/bin/certbot /usr/bin/certbot

    echo -e "${YELLOW}Obtaining and installing SSL certificate...${NC}"
    read -rp "Enter your email address for SSL certificate: " email_address
    sudo certbot --nginx --non-interactive --agree-tos --email "$email_address" -d "$site_name"
    echo -e "${GREEN}SSL certificate installed successfully.${NC}"
    sleep 2
else
    echo -e "${RED}Skipping SSL installation.${NC}"
    sleep 2
fi

# Final permissions and cleanup
echo -e "${YELLOW}Applying final permissions...${NC}"
sudo chmod -R 755 "$HOME/frappe-bench"
echo -e "${GREEN}Permissions applied.${NC}"
sleep 2

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
