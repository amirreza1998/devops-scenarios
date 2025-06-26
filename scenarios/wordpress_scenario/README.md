# 🐳 Dockerized WordPress Environment Setup

This guide provides a complete, automated setup for a production-ready WordPress environment using Docker containers with Nginx reverse proxy, SSL certificate, and MySQL database.

## 📋 Overview

This setup creates a robust WordPress environment that includes:
- **Nginx** as a reverse proxy with SSL termination
- **WordPress** application container
- **MySQL 5.7** database
- **Self-signed SSL certificate** for HTTPS
- **Docker networking** for container communication
- **Persistent volumes** for data storage

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     Nginx       │────│   WordPress     │────│     MySQL       │
│  (Reverse Proxy)│    │  (Application)  │    │   (Database)    │
│   Ports: 80,443 │    │   Port: 80      │    │   Port: 3306    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                         Docker Network (wp_net)
```

## 🚀 Quick Start

### Prerequisites

- Docker installed and running
- OpenSSL for certificate generation
- Bash shell environment
- Root or sudo access (for /etc/hosts modification)

### Automated Setup

Run the complete setup script:

```bash
chmod +x runnerbash.sh
./runnerbash.sh
```

### Manual Step-by-Step Setup

If you prefer to understand each step, follow the detailed process below:

## 📖 Detailed Setup Process

### Step 1: Configuration Variables

First, set up the environment variables for your deployment:

```bash
#!/bin/bash
set -e

# === CONFIGURATION ===
DOMAIN_NAME="amirrezakzm.ir"
PROJECT_DIR_NAME="wordpress-stack"
NETWORK_NAME="wp_net"
DB_VOLUME="wp_db_data"
WP_VOLUME="wp_files_data"

# Generate secure random passwords
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
MYSQL_PASSWORD=$(openssl rand -base64 32)
MYSQL_DATABASE="wordpress"
MYSQL_USER="wordpress"
```

**Configuration Details:**
- `DOMAIN_NAME`: Your domain (update this to your actual domain)
- `PROJECT_DIR_NAME`: Local directory for configuration files
- `NETWORK_NAME`: Docker network name for container communication
- `DB_VOLUME` & `WP_VOLUME`: Persistent storage volumes
- Passwords are automatically generated using OpenSSL for security

### Step 2: Environment Cleanup

Clean up any existing containers and project directories:

```bash
echo "--- Step 1: Cleaning up any previous environment... ---"

# Stop and remove containers (ignore errors if they don't exist)
docker stop nginx wordpress mysql &> /dev/null || true
docker rm nginx wordpress mysql &> /dev/null || true

# Remove old project directory
if [ -d "./${PROJECT_DIR_NAME}" ]; then
    echo "Removing old project directory: ./${PROJECT_DIR_NAME}"
    rm -rf "./${PROJECT_DIR_NAME}"
fi

echo "Cleanup complete."
```

**Why this step?**
- Ensures a clean environment
- Prevents conflicts with existing containers
- Removes old configuration files

### Step 3: Host Environment Setup

Create the necessary directory structure:

```bash
echo "--- Step 2: Setting up host environment... ---"

# Create project directories
mkdir -p "./${PROJECT_DIR_NAME}/nginx/conf.d"
mkdir -p "./${PROJECT_DIR_NAME}/nginx/certs"

echo "Project directories created in ./${PROJECT_DIR_NAME}"
echo
echo "IMPORTANT: Make sure this line is in your /etc/hosts file:"
echo "127.0.0.1   ${DOMAIN_NAME}"
```

**Directory Structure:**
```
wordpress-stack/
├── nginx/
│   ├── conf.d/          # Nginx configuration files
│   └── certs/           # SSL certificates
```

**Important:** Add the domain to your `/etc/hosts` file:
```bash
sudo echo "127.0.0.1   amirrezakzm.ir" >> /etc/hosts
```

### Step 4: Docker Resources Creation

Set up Docker network and volumes:

```bash
echo "--- Step 3: Creating Docker network and volumes... ---"

# Create Docker network for container communication
docker network create "${NETWORK_NAME}"

# Create persistent volumes for data storage
docker volume create "${DB_VOLUME}"
docker volume create "${WP_VOLUME}"

echo "Network and volumes created."
```

**Resource Details:**
- **Network**: Allows containers to communicate by hostname
- **DB Volume**: Persists MySQL data across container restarts
- **WP Volume**: Persists WordPress files and uploads

### Step 5: SSL Certificate Generation

Generate a self-signed SSL certificate:

```bash
echo "--- Step 4: Generating self-signed SSL certificate... ---"

openssl req -x509 -nodes -newkey rsa:4096 -days 365 \
    -keyout "./${PROJECT_DIR_NAME}/nginx/certs/key.pem" \
    -out "./${PROJECT_DIR_NAME}/nginx/certs/cert.pem" \
    -subj "/C=IR/ST=Tehran/L=Tehran/O=DockerMe/CN=${DOMAIN_NAME}"

echo "SSL certificate and key generated."
```

**Certificate Details:**
- **Algorithm**: RSA 4096-bit encryption
- **Validity**: 365 days
- **Location**: IR/Tehran (customize as needed)
- **Files**: `cert.pem` (certificate) and `key.pem` (private key)

### Step 6: Nginx Configuration

Create the Nginx configuration file:

```bash
echo "--- Step 5: Creating Nginx configuration file... ---"

cat <<EOF > "./${PROJECT_DIR_NAME}/nginx/conf.d/wordpress.conf"
# HTTP to HTTPS redirect
server {
    listen 80;
    server_name ${DOMAIN_NAME};
    return 301 https://\$host\$request_uri;
}

# HTTPS server block
server {
    listen 443 ssl http2;
    server_name ${DOMAIN_NAME};

    # SSL configuration
    ssl_certificate /etc/nginx/certs/cert.pem;
    ssl_certificate_key /etc/nginx/certs/key.pem;

    # Modern SSL settings for security
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
    ssl_ecdh_curve secp384r1;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # Reverse proxy to WordPress
    location / {
        proxy_pass http://wordpress:80;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
```

**Configuration Features:**
- **HTTP to HTTPS redirect**: Automatically redirects all HTTP traffic to HTTPS
- **Modern SSL settings**: Uses latest TLS protocols and secure ciphers
- **Security headers**: HSTS, XSS protection, clickjacking prevention
- **Reverse proxy**: Forwards requests to WordPress container

### Step 7: Container Deployment

Deploy containers in the correct order:

#### 7.1 MySQL Database Container

```bash
echo "Starting MySQL container..."

docker run -d \
    --name mysql \
    --network "${NETWORK_NAME}" \
    --hostname mysql \
    --restart=always \
    --volume "${DB_VOLUME}:/var/lib/mysql" \
    -e MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
    -e MYSQL_DATABASE="${MYSQL_DATABASE}" \
    -e MYSQL_USER="${MYSQL_USER}" \
    -e MYSQL_PASSWORD="${MYSQL_PASSWORD}" \
    mysql:5.7
```

**MySQL Configuration:**
- **Image**: MySQL 5.7 (stable and WordPress compatible)
- **Network**: Connected to custom network
- **Volume**: Persistent data storage
- **Environment**: Database and user automatically created

#### 7.2 Wait for MySQL Readiness

```bash
echo "Waiting for MySQL to be ready..."
while ! docker logs mysql 2>&1 | grep -q "mysqld: ready for connections."; do
    sleep 2
done
echo "MySQL is ready!"
```

**Why wait?**
- MySQL needs time to initialize
- WordPress container will fail if database isn't ready
- This prevents race conditions

#### 7.3 WordPress Application Container

```bash
echo "Starting WordPress container..."

docker run -d \
    --name wordpress \
    --network "${NETWORK_NAME}" \
    --hostname wordpress \
    --restart=always \
    --volume "${WP_VOLUME}:/var/www/html" \
    -e WORDPRESS_DB_HOST=mysql:3306 \
    -e WORDPRESS_DB_NAME="${MYSQL_DATABASE}" \
    -e WORDPRESS_DB_USER="${MYSQL_USER}" \
    -e WORDPRESS_DB_PASSWORD="${MYSQL_PASSWORD}" \
    wordpress:latest
```

**WordPress Configuration:**
- **Image**: Latest WordPress (automatically updated)
- **Database connection**: Points to MySQL container by hostname
- **Volume**: Persistent WordPress files and uploads

#### 7.4 Nginx Reverse Proxy Container

```bash
echo "Starting Nginx container..."

docker run -d \
    --name nginx \
    --network "${NETWORK_NAME}" \
    --hostname nginx \
    --restart=always \
    -p 80:80 \
    -p 443:443 \
    -v "./${PROJECT_DIR_NAME}/nginx/conf.d:/etc/nginx/conf.d:ro" \
    -v "./${PROJECT_DIR_NAME}/nginx/certs:/etc/nginx/certs:ro" \
    nginx:latest
```

**Nginx Configuration:**
- **Ports**: 80 (HTTP) and 443 (HTTPS) exposed to host
- **Configuration**: Mounted as read-only volume
- **Certificates**: SSL certificates mounted as read-only

### Step 8: Verification and Testing

Verify the setup is working:

```bash
echo "--- Step 7: Verifying the setup... ---"

# Give Nginx a moment to start
sleep 5

echo "Testing HTTPS connection..."
curl --head --location --insecure "https://${DOMAIN_NAME}"

echo "✅ Setup Complete! Access https://${DOMAIN_NAME} in your browser."
```

## 🔧 Troubleshooting

### Common Issues

1. **Domain not resolving:**
   ```bash
   # Check /etc/hosts file
   cat /etc/hosts | grep amirrezakzm.ir
   
   # Add if missing
   echo "127.0.0.1 amirrezakzm.ir" | sudo tee -a /etc/hosts
   ```

2. **Containers not starting:**
   ```bash
   # Check container status
   docker ps -a
   
   # View container logs
   docker logs mysql
   docker logs wordpress
   docker logs nginx
   ```

3. **SSL certificate issues:**
   ```bash
   # Regenerate certificates
   rm -rf ./wordpress-stack/nginx/certs/*
   # Run certificate generation step again
   ```

4. **Port conflicts:**
   ```bash
   # Check what's using ports 80/443
   sudo netstat -tlnp | grep :80
   sudo netstat -tlnp | grep :443
   ```

### Useful Commands

```bash
# View all containers
docker ps

# Check container logs
docker logs -f wordpress

# Access WordPress container
docker exec -it wordpress bash

# Access MySQL container
docker exec -it mysql mysql -u root -p

# Stop all containers
docker stop nginx wordpress mysql

# Remove all containers
docker rm nginx wordpress mysql

# Remove network and volumes
docker network rm wp_net
docker volume rm wp_db_data wp_files_data
```

## 🔐 Security Considerations

- **Self-signed certificates**: Use Let's Encrypt for production
- **Database passwords**: Automatically generated and secure
- **Network isolation**: Containers communicate on isolated network
- **Security headers**: HSTS, XSS protection, and clickjacking prevention
- **SSL settings**: Modern TLS protocols and secure ciphers

## 📊 Default Credentials

After setup, access your WordPress installation:

- **URL**: https://amirrezakzm.ir
- **WordPress Admin**: Create during first visit
- **Database**: Automatically configured
- **MySQL Root Password**: Generated and displayed during setup

## 🎯 Next Steps

1. **Complete WordPress setup** through the web interface
2. **Configure your domain** in WordPress settings
3. **Install SSL certificate** from a trusted CA for production
4. **Set up backups** for database and WordPress files
5. **Configure monitoring** and logging

## 📝 File Structure

After completion, your project structure will be:

```
wordpress-stack/
├── nginx/
│   ├── conf.d/
│   │   └── wordpress.conf    # Nginx configuration
│   └── certs/
│       ├── cert.pem          # SSL certificate
│       └── key.pem           # SSL private key
└── runnerbash.sh             # Setup script
```

---

**Note**: This setup is designed for development and testing. For production use, consider using Let's Encrypt for SSL certificates and implementing additional security measures.






## Step2: running wordpress with compose-file and docker-compose

### compose file
```bash
---
version: '3.8'

networks:
  wp_net:
    name: wp_net
    driver_opts:
      com.docker.network.bridge.name: wp_net

volumes:
  wp_db:
    name: wp_db
  wp_wp:
    name: wp_wp

services:
  db:
    image: mysql:5.7
    container_name: mysql
    volumes:
      - wp_db:/var/lib/mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: sdfascsdvsfdvweliuoiquowecefcwaefef
      MYSQL_DATABASE: DockerMe
      MYSQL_USER: DockerMe
      MYSQL_PASSWORD: sdfascsdvsfdvweliuoiquowecefcwaefef
    networks:
      - wp_net

  wordpress:
    image: wordpress:latest
    container_name: wordpress
    volumes:
      - wp_wp:/var/www/html/
    depends_on:
      - db
    restart: always
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: DockerMe
      WORDPRESS_DB_NAME: DockerMe
      WORDPRESS_DB_PASSWORD: sdfascsdvsfdvweliuoiquowecefcwaefef
    ports:
      - 8000:80
    networks:
      - wp_net

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: always
    depends_on:
      - wordpress
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/certs:/etc/nginx/certs
    ports:
      - 80:80
      - 443:443
    networks:
      - wp_net
```
### check and run compose file
```bash
docker-compose config
docker-compose up -d
docker-compose logs -f
docker-compose ps