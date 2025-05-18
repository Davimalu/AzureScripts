#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

AGENT_ALLOW_RUNASROOT=true # maybe create a dedicated user instead
mkdir azagent;cd azagent;curl -fkSL -o vstsagent.tar.gz https://download.agent.dev.azure.com/agent/4.255.0/vsts-agent-linux-x64-4.255.0.tar.gz;tar -zxvf vstsagent.tar.gz; if [ -x "$(command -v systemctl)" ]; then ./config.sh --environment --environmentname "MTCG-Prod-VMs" --acceptteeeula --agent $HOSTNAME --url https://dev.azure.com/FHTW-DEVSEC/ --work _work --projectname 'DEVSEC' --auth PAT --token $0 --runasservice; sudo ./svc.sh install; sudo ./svc.sh start; else ./config.sh --environment --environmentname "MTCG-Prod-VMs" --acceptteeeula --agent $HOSTNAME --url https://dev.azure.com/FHTW-DEVSEC/ --work _work --projectname 'DEVSEC' --auth PAT --token $0; ./run.sh; fi
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
