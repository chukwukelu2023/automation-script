#!/bin/bash

timestamp=$(date +"%Y%m%d")
log_file="deploy_${timestamp}.log"

exec > >(tee -a "$log_file") 2>&1

echo "Deploying app..."

echo -e "\n Enter repo url"

read  repo_url

echo -e "\n Enter Repo PAT"

read repo_pat

echo -e "\n Enter Branch name (optional, default is main )"

read branch_name

echo -e "\n Enter Server Username"

read server_user

echo -e "\n Enter Server IP"

read server_ip

echo -e "\n Enter Server Key Path"

read server_key_path

echo -e "\n Enter Application Port"

read app_port

echo $repo_url
echo $repo_pat
echo $branch_name
echo $server_user
echo $server_ip
echo $server_key_path
echo $app_port

if [ "$branch_name" = "" ]; then
  branch_name="main"
fi



# Extract repo name

repo_url_no_git=${repo_url%.git}
repo_name=${repo_url_no_git##*/}

if [ -d "$repo_name" ]; then
    echo "Repository $repo_name already exists."
    cd "$repo_name"
    git checkout $branch_name
    git pull origin $branch_name
else
    echo "Cloning repository....." 
    git clone -b $branch_name https://${repo_pat}@${repo_url#https://}
    cd "$repo_name"

fi    

if [ -f "docker-compose.yml" ] || [ -f "Dockerfile" ]; then
    echo "Docker file and/or docker compose file exists"
    echo "Docker file and/or docker compose file exists: $log_file"
else
    echo "Docker file or docker compose file does not exists"
    echo "Docker file or docker compose file does not exists: $log_file"
    exit 1
fi

# SSH into the Remote Server

echo "Testing connection to server ...."

ping $server_ip -c 5

echo "Connectinh to server..."

chmod 600 "$server_key_path"

ssh -i $server_key_path -o StrictHostKeyChecking=no  $server_user@$server_ip << 'ENDSSH'
    echo "Connected to $(hostname)"
    echo "Updating system packages..."
    sudo apt update -y
    if command -v docker >/dev/null 2>&1; then
        echo "Docker is already installed."
        docker --version
    else
        echo "Installing Docker..."
       

        # Add Docker's official GPG key:
        sudo apt-get update
        sudo apt-get install ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources:
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update

        sudo usermod -aG docker $USER
        sudo systemctl start docker
        docker --version
    fi

    if command -v docker-compose &> /dev/null; then
        echo "Docker Compose already installed"
        docker compose version 
    else
        echo "🔧 Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
         -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo "Docker Compose installed successfully"
        docker compose version 
    fi

    if dpkg -s nginx &> /dev/null; then
       echo "Nginx already installed"
    else
        echo "Installing Nginx..."
        sudo apt install -y nginx
        sudo systemctl enable nginx
        sudo systemctl start nginx
        echo "Nginx installed successfully"
    fi

    echo "Setup complete on $(hostname)"
ENDSSH


scp -i $server_key_path -r . $server_user@$server_ip:/home/$server_user/


ssh -i "$server_key_path" -o StrictHostKeyChecking=no "$server_user@$server_ip" << 'ENDSSH'
set -e

if [ -f "Dockerfile" ] ; then
    echo "Building and running Docker manually..."
    sudo docker build -t app .
    sudo docker stop app || true
    sudo docker rm app || true
    sudo docker run -d -p $app_port:$app_port --name app app
    sudo docker logs app --tail 20
    curl -I http://localhost:$app_port
else
    
    echo "Starting with Docker Compose..."
    sudo docker compose down || true
    sudo docker compose up --build -d
fi

echo "Deployment complete on $(hostname)"

ENDSSH


ssh -i "$server_key_path" -o StrictHostKeyChecking=no "$server_user@$server_ip" << 'ENDSSH'
set -e

APP_PORT=8000
NGINX_CONF="/etc/nginx/sites-available/app.conf"
NGINX_LINK="/etc/nginx/sites-enabled/app.conf"

echo "🌐 Configuring Nginx reverse proxy..."

# Create or overwrite nginx config
sudo bash -c "cat > $NGINX_CONF" <<EOF
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

# Enable the site and disable the default if necessary
sudo ln -sf "$NGINX_CONF" "$NGINX_LINK"
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx config for syntax errors
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx
sudo systemctl enable nginx


ENDSSH
