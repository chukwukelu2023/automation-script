#!/bin/bash
set -euo pipefail

timestamp=$(date +"%Y%m%d_%H%M%S")
log_file="deploy_${timestamp}.log"
exec > >(tee -a "$log_file") 2>&1

echo "Starting deployment at $(date)"
echo "Log file: $log_file"

read -p "Enter repo URL: " repo_url
read -p "Enter Repo PAT: " repo_pat
read -p "Enter Branch name (default: main): " branch_name
read -p "Enter Server Username: " server_user
read -p "Enter Server IP: " server_ip
read -p "Enter Server Key Path: " server_key_path
read -p "Enter Application Port: " app_port


if [[ ! "$repo_url" =~ ^https://github\.com/.+/.+\.git$ ]]; then
  echo "Invalid GitHub repository URL: $repo_url"
  exit 1
fi

if [[ -z "$repo_pat" ]]; then
  echo "GitHub Personal Access Token cannot be empty"
  exit 1
fi

if [[ -z "$server_user" ]]; then
  echo "Server username cannot be empty"
  exit 1
fi

if [[ ! "$server_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Invalid IP address: $server_ip"
  exit 1
else
  if ! ping -c 2 -W 2 "$server_ip" &> /dev/null; then
    echo "Server $server_ip is unreachable"
    exit 1
  fi
fi

if [[ ! -f "$server_key_path" ]]; then
  echo "SSH key file not found at: $server_key_path"
  exit 1
fi
chmod 600 "$server_key_path"


if ! [[ "$app_port" =~ ^[0-9]+$ ]] || (( app_port < 1 || app_port > 65535 )); then
  echo "Invalid port number: $app_port (must be 1–65535)"
  exit 1
fi

echo "All input validations passed."


branch_name=${branch_name:-main}

repo_url_no_git=${repo_url%.git}
repo_name=${repo_url_no_git##*/}

if [ -d "$repo_name" ]; then
    echo "Updating existing repository $repo_name..."
    cd "$repo_name"
    git checkout "$branch_name"
    git pull origin "$branch_name"
else
    echo "Cloning repository..."
    git clone -b "$branch_name" "https://${repo_pat}@${repo_url#https://}"
    cd "$repo_name"
fi    

if ! [ -f "docker-compose.yml" ] && ! [ -f "Dockerfile" ]; then
    echo "No Dockerfile or docker-compose.yml found!"
    exit 1
fi

if ! ping -c 2 "$server_ip" >/dev/null 2>&1; then
  echo "Server $server_ip not reachable"
  exit 1
fi


# Copy files to server
ssh -i "$server_key_path" "$server_user@$server_ip" "rm -rf ~/app && mkdir ~/app"
scp -i "$server_key_path" -r . "$server_user@$server_ip:~/app"

# SSH into server and deploy
ssh -i "$server_key_path" -o StrictHostKeyChecking=no "$server_user@$server_ip" << ENDSSH
set -e

echo "Connected to $(hostname)"
echo "Updating system packages..."
sudo apt update -y

# Install Docker
if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker..."
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \${UBUNTU_CODENAME:-\$VERSION_CODENAME}) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$server_user"
  sudo systemctl enable docker --now
else
  echo "Docker already installed."
fi

# Install Nginx
if ! dpkg -s nginx >/dev/null 2>&1; then
  echo "Installing Nginx..."
  sudo apt install -y nginx
  sudo systemctl enable nginx --now
fi

cd ~/app

if [ -f "docker-compose.yml" ]; then
    echo "Running Docker Compose..."
    sudo docker compose down || true
    sudo docker compose up --build -d
else
    echo "Building and running single Dockerfile app..."
    sudo docker stop app || true
    sudo docker rm app || true
    sudo docker build -t app .
    sudo docker run -d -p $app_port:$app_port --name app app
fi

# Configure Nginx
NGINX_CONF="/etc/nginx/sites-available/app.conf"
NGINX_LINK="/etc/nginx/sites-enabled/app.conf"

echo "Configuring Nginx reverse proxy..."
sudo bash -c "cat > \$NGINX_CONF" <<'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:$app_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -sf "\$NGINX_CONF" "\$NGINX_LINK"
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx

curl -I http://localhost || true
echo "Deployment complete on \$(hostname)"
ENDSSH

echo "Deployment finished at $(date)"
