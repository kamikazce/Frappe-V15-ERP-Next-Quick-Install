# Update system packages
sudo apt update && sudo apt upgrade -y

# Install essential dependencies
sudo apt install -y software-properties-common git curl wget gnupg build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev libbz2-dev python3-dev python3-venv python3-pip redis-server mariadb-server mariadb-client snapd

# Create a dedicated frappe user
sudo adduser frappe

# Grant frappe user sudo privileges
sudo usermod -aG sudo frappe

# Switch to frappe user
su - frappe

# Clone the installer repository
git clone https://github.com/kamikazce/Frappe-V15-ERP-Next-Quick-Install.git

# Navigate to the installer directory
cd Frappe-V15-ERP-Next-Quick-Install

# Make the installer script executable
chmod +x install_frappe.sh

# Run the installer script
./install_frappe.sh

