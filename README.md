# 🚀 Automated Deployment Bash Script

This Bash script automates the deployment of any **containerized application** to a **remote Linux server**.  
It clones your GitHub repository, installs required dependencies, and deploys your app using **Docker** and **Nginx** as a reverse proxy.

---

## 🧠 Overview

The script performs these key steps:

1. Clones your repository using a **GitHub Personal Access Token (PAT)**.  
2. Connects securely to your **remote server** via SSH.  
3. Ensures **Docker**, **Docker Compose**, and **Nginx** are installed and running.  
4. Deploys your app container using a `Dockerfile` or `docker-compose.yml`.  
5. Configures **Nginx** to route HTTP (port 80) traffic to your container’s internal port.  
6. Logs all deployment actions in a timestamped file (e.g., `deploy_20251021.log`).

---

## ⚙️ Prerequisites

- A GitHub repository containing a `Dockerfile` or `docker-compose.yml`
- A GitHub **Personal Access Token (PAT)** with repo read access  
- A **remote Ubuntu server** accessible via SSH  
- Your **private SSH key (.pem)** file with proper permissions (`chmod 600`)  
- Bash and Git installed locally

---

## 🔧 Required Inputs

When you run the script, it will prompt you for:

| Input | Description | Required |
|--------|--------------|----------|
| Repository URL | HTTPS GitHub repository URL | ✅ |
| Repository PAT | GitHub Personal Access Token | ✅ |
| Branch Name | Optional (defaults to `main`) | ❌ |
| Server Username | Remote server SSH username | ✅ |
| Server IP Address | Remote server public IP | ✅ |
| Server Key Path | Path to SSH key file | ✅ |
| Application Port | Port exposed by your app | ✅ |

---

## 🧩 Server Configuration

Once connected, the script ensures the following are installed and running:

- **Docker**
- **Docker Compose**
- **Nginx**

Nginx is configured automatically as a reverse proxy, forwarding HTTP traffic on port **80** to your application.

---

## 🚀 Deployment Process

1. The script validates all inputs (repo URL, IP, SSH key, etc.)  
2. Clones the target branch of your repository  
3. Copies the repository to the remote server via **SCP**  
4. Builds and runs the container using Docker or Docker Compose  
5. Configures Nginx to proxy traffic to the running container  
6. Logs all actions to a timestamped file

> ⚠️ Ensure your repository contains either a `Dockerfile` or a `docker-compose.yml`.  
> The deployment will fail otherwise.

---

## 🪵 Logging

All output is logged to a file named: e.g `deploy_YYYYMMDD`


This log file includes every action taken during the deployment.

---

## 🧰 Usage

```bash
chmod +x deploy.sh
./deploy.sh
````
Once deployment completes, verify by running:
````
curl -I http://<your-server-ip>
````
You should see an HTTP 200 OK response if the deployment was successful.