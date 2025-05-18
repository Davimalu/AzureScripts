#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

mkdir azagent;cd azagent;curl -fkSL -o vstsagent.tar.gz https://download.agent.dev.azure.com/agent/4.255.0/vsts-agent-linux-x64-4.255.0.tar.gz;tar -zxvf vstsagent.tar.gz; if [ -x "$(command -v systemctl)" ]; then AGENT_ALLOW_RUNASROOT="1" ./config.sh --environment --unattended --environmentname "MTCG-Prod-VMs" --acceptteeeula --agent $HOSTNAME --url https://dev.azure.com/FHTW-DEVSEC/ --work _work --projectname 'DEVSEC' --auth PAT --token $1 --runasservice; sudo ./svc.sh install; sudo ./svc.sh start; else ./config.sh --environment --environmentname "MTCG-Prod-VMs" --acceptteeeula --agent $HOSTNAME --url https://dev.azure.com/FHTW-DEVSEC/ --work _work --projectname 'DEVSEC' --auth PAT --token $1; ./run.sh; fi

# --- Docker Installation (Example for Debian/Ubuntu) ---
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install Dotnet Core
sudo apt update && sudo apt install -y aspnetcore-runtime-8.0

exit 0
