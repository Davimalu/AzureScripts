#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration Variables ---
# Mandatory: PA_TOKEN should be passed as the first argument to the script.
# Example: ./setup_agent.sh <YOUR_PA_TOKEN>

# Default Azure DevOps settings (can be overridden by environment variables)
AZURE_DEVOPS_URL="${AZURE_DEVOPS_URL:-"https://dev.azure.com/FHTW-DEVSEC/"}"
AZURE_DEVOPS_PROJECT_NAME="${AZURE_DEVOPS_PROJECT_NAME:-"DEVSEC"}"
AZURE_DEVOPS_ENVIRONMENT_NAME="${AZURE_DEVOPS_ENVIRONMENT_NAME:-"MTCG-Prod-VMs"}"

# Agent download URL (Linux x64) - using the version from your example
# If you need the latest official agent, this URL will need to be updated.
# e.g., latest_version=$(curl -s https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | cut -c 2-)
# AGENT_DOWNLOAD_URL="https://vstsagentpackage.azureedge.net/agent/${latest_version}/vsts-agent-linux-x64-${latest_version}.tar.gz"
AGENT_DOWNLOAD_URL="${AGENT_DOWNLOAD_URL:-"https://download.agent.dev.azure.com/agent/4.255.0/vsts-agent-linux-x64-4.255.0.tar.gz"}"

# Agent installation settings
AGENT_BASE_INSTALL_DIR="${AGENT_BASE_INSTALL_DIR:-"/opt/azagent"}" # Base directory for all agents
AGENT_NAME="${AGENT_NAME:-"$HOSTNAME"}" # Default agent name to machine hostname
AGENT_WORK_DIR="${AGENT_WORK_DIR:-"_work"}" # Default work directory for the agent

# --- Logging Function ---
log() {
    echo "AGENT_SCRIPT_LOG: $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# --- Helper Functions ---
check_root() {
    log "Checking for root privileges..."
    if [ "$(id -u)" -ne 0 ]; then
        log "Error: This script must be run as root or with sudo."
        exit 1
    fi
    log "Root privileges confirmed."
}

# --- Main Script Logic ---

log "Starting Azure DevOps Agent registration and Docker installation script."

# Check for PAToken
PA_TOKEN="${1}"
if [ -z "$PA_TOKEN" ]; then
    log "Error: Personal Access Token (PAToken) is required."
    log "Usage: $0 <PAToken>"
    exit 1
fi
log "PAToken provided." # Do not log the token itself

# Ensure script is run as root, as it performs installations and service setups
check_root

# --- Azure DevOps Agent Setup ---
log "=== Starting Azure DevOps Agent Setup ==="

# Create agent base installation directory
log "Ensuring agent base installation directory exists: $AGENT_BASE_INSTALL_DIR"
if [ ! -d "$AGENT_BASE_INSTALL_DIR" ]; then
    mkdir -p "$AGENT_BASE_INSTALL_DIR"
    # chown to current user if needed, but script runs as root anyway
    # current_user=$(logname)
    # chown -R "$current_user":"$(id -gn "$current_user")" "$AGENT_BASE_INSTALL_DIR"
    log "Created directory: $AGENT_BASE_INSTALL_DIR"
fi
original_dir=$(pwd)
cd "$AGENT_BASE_INSTALL_DIR"
log "Changed current directory to: $(pwd)"

# Create unique subfolder for the agent
agent_sub_folder_path=""
for i in $(seq 1 99); do
    dest_folder_name="A${i}"
    if [ ! -d "$dest_folder_name" ]; then
        mkdir "$dest_folder_name"
        agent_sub_folder_path="$(pwd)/$dest_folder_name"
        log "Created agent subfolder: $agent_sub_folder_path"
        cd "$dest_folder_name"
        log "Changed current directory to: $(pwd)"
        break
    fi
done

if [ -z "$agent_sub_folder_path" ]; then
    log "Error: Could not create a unique agent subfolder in $AGENT_BASE_INSTALL_DIR."
    cd "$original_dir"
    exit 1
fi

# Define paths for agent files
agent_tarball_name="vstsagent.tar.gz"
agent_tarball_path="$agent_sub_folder_path/$agent_tarball_name"
config_script_path="$agent_sub_folder_path/config.sh"

if [ -f "$config_script_path" ]; then
    log "Agent configuration script (config.sh) already exists at '$config_script_path'. Skipping download and extraction."
    log "If you want to reconfigure, please remove the directory $agent_sub_folder_path and re-run."
else
    log "Agent configuration script not found. Proceeding with download and extraction."
    # Download agent
    log "Downloading Azure DevOps Agent from $AGENT_DOWNLOAD_URL to $agent_tarball_path..."
    # Note: If behind a proxy, ensure http_proxy and https_proxy environment variables are set.
    # The original PowerShell script had specific proxy handling; curl relies on these env vars.
    # Using -fsSL: fail silently on server errors, show error on client, follow redirects.
    if curl -fsSL "$AGENT_DOWNLOAD_URL" -o "$agent_tarball_path"; then
        log "Agent downloaded successfully."
    else
        log "Error: Failed to download agent. Check URL and network connectivity."
        cd "$original_dir"
        exit 1
    fi

    # Extract agent
    log "Extracting agent from $agent_tarball_path to $agent_sub_folder_path..."
    if tar -zxvf "$agent_tarball_path" -C "$agent_sub_folder_path" > /dev/null; then
        log "Agent extracted successfully."
    else
        log "Error: Failed to extract agent."
        cd "$original_dir"
        exit 1
    fi

    # Configure agent
    log "Configuring agent with the following parameters:"
    log "  Agent Name: $AGENT_NAME"
    log "  Environment Name: $AZURE_DEVOPS_ENVIRONMENT_NAME"
    log "  Azure DevOps URL: $AZURE_DEVOPS_URL"
    log "  Project Name: $AZURE_DEVOPS_PROJECT_NAME"
    log "  Work Directory: $AGENT_WORK_DIR"
    log "  Authentication Type: PAT (Token will not be logged)"
    log "  Unattended setup: Yes"
    log "  Accept TEE EULA: Yes"

    if [ ! -x "$config_script_path" ]; then
        log "Error: Configuration script $config_script_path not found or not executable after extraction."
        cd "$original_dir"
        exit 1
    fi
    
    # Grant execute permissions to the scripts in the agent directory
    chmod +x $agent_sub_folder_path/*.sh

    # Configuration arguments
    # Note: --acceptteeeula is important for unattended setup.
    config_args=(
        "--environment"
        "--environmentname" "$AZURE_DEVOPS_ENVIRONMENT_NAME"
        "--agent" "$AGENT_NAME"
        "--url" "$AZURE_DEVOPS_URL"
        "--work" "$AGENT_WORK_DIR"
        "--projectname" "$AZURE_DEVOPS_PROJECT_NAME"
        "--auth" "PAT"
        "--token" "$PA_TOKEN"
        "--unattended"
        "--acceptteeeula"
    )

    log "Executing agent configuration: $config_script_path ${config_args[*]}"
    # The PAToken is sensitive, so it's part of the command but not explicitly re-logged here.

    # Execute config.sh from within the agent's directory
    # cd "$agent_sub_folder_path" # Already in this directory
    
    if "$config_script_path" "${config_args[@]}"; then
        log "Agent configuration script (config.sh) completed successfully."

        # Install and start service if systemctl is available
        if [ -x "$(command -v systemctl)" ]; then
            log "systemctl detected. Setting up agent as a service."
            svc_script_path="$agent_sub_folder_path/svc.sh"
            if [ ! -f "$svc_script_path" ]; then
                log "Error: $svc_script_path not found. Cannot setup service."
            else
                log "Installing agent service..."
                if sudo "$svc_script_path" install; then
                    log "Agent service installed."
                    log "Starting agent service..."
                    if sudo "$svc_script_path" start; then
                        log "Agent service started."
                    else
                        log "Error: Failed to start agent service. Check service logs."
                    fi
                else
                    log "Error: Failed to install agent service."
                fi
            fi
        else
            log "systemctl not found. Agent configured but not started as a service."
            log "You can run the agent manually using: $agent_sub_folder_path/run.sh"
        fi
    else
        log "Error: Agent configuration script (config.sh) failed. Exit code: $?"
        cd "$original_dir"
        exit 1
    fi

    # Clean up downloaded agent tarball
    log "Removing agent tarball: $agent_tarball_path"
    rm -f "$agent_tarball_path"
    log "Agent tarball removed."
fi
log "=== Azure DevOps Agent Setup Finished ==="

# Return to original directory
cd "$original_dir"
log "Changed current directory back to: $(pwd)"


# --- Docker Installation (Example for Debian/Ubuntu) ---
install_docker_debian_ubuntu() {
    log "=== Starting Docker Engine Installation (Debian/Ubuntu) ==="
    log "Checking if Docker is already installed..."
    if command -v docker &> /dev/null; then
        log "Docker appears to be already installed. Version: $(docker --version)"
        log "Skipping Docker installation."
        return
    fi

    log "Docker not found. Proceeding with installation for Debian/Ubuntu."
    log "Updating package list..."
    apt-get update -y

    log "Installing prerequisites..."
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    log "Adding Docker's official GPG key..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    if [ $? -ne 0 ]; then
        log "Error adding Docker GPG key. Trying alternative for older systems."
        curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | apt-key add -
         if [ $? -ne 0 ]; then
            log "Error adding Docker GPG key via apt-key as well. Please check your system or install Docker manually."
            return 1 # Indicate failure
        fi
    fi
    
    log "Setting up Docker stable repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    log "Updating package list again after adding Docker repo..."
    apt-get update -y

    log "Installing Docker Engine, CLI, and Containerd..."
    if apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log "Docker Engine installed successfully."
        log "Docker version: $(docker --version)"
        # You might want to add the current user to the docker group:
        # log "To run docker commands without sudo, add your user to the docker group:"
        # log "sudo usermod -aG docker \$USER"
        # log "Then, log out and log back in for the changes to take effect."
    else
        log "Error: Failed to install Docker Engine."
        return 1 # Indicate failure
    fi
    log "=== Docker Engine Installation Finished ==="
    return 0
}

# --- Execute Docker Installation ---
# Check OS and call the appropriate Docker installation function.
# This example only includes Debian/Ubuntu.
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
        install_docker_debian_ubuntu
        if [ $? -ne 0 ]; then
            log "Docker installation encountered an error."
        fi
    else
        log "Docker installation for OS '$ID' is not automatically handled by this script."
        log "Please install Docker manually if required: https://docs.docker.com/engine/install/"
    fi
else
    log "Cannot determine OS type. Skipping automatic Docker installation."
    log "Please install Docker manually if required: https://docs.docker.com/engine/install/"
fi

log "Azure DevOps Agent registration and Docker installation script finished."

sudo apt update && sudo apt install -y aspnetcore-runtime-8.0

exit 0
