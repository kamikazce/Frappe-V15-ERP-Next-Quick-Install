Setting Up WSL
If you haven't set up WSL yet, follow these steps:

Enable WSL:

bash
Copy code
wsl --install
This command installs the latest WSL version along with the default Ubuntu distribution.

Update WSL (if already installed):

bash
Copy code
wsl --update
Launch Ubuntu: Open the Ubuntu application from the Start menu and complete the initial setup.

Installation
Follow the steps below to install Frappe V15 and ERPNext using the provided installer script.

Step 1: Clone the Repository
First, clone the repository to your local machine using git:

bash
Copy code
git clone https://github.com/kamikazce/Frappe-V15---ERP-Next-Quick-Install.git
Step 2: Navigate to the Directory
Change your current directory to the cloned repository:

bash
Copy code
cd Frappe-V15---ERP-Next-Quick-Install
Step 3: Make the Installer Executable
Modify the permissions of the installer script to make it executable:

bash
Copy code
chmod +x install_frappe.sh
Step 4: Run the Installer
Execute the installer script with sudo privileges:

bash
Copy code
./install_frappe.sh
Note: The script will prompt you for various inputs, such as MariaDB root password, site name, administrator password, and options to install ERPNext and SSL.
