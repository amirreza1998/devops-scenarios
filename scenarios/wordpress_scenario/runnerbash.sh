#!/bin/bash
#
# This script creates a complete Dockerized WordPress environment from scratch.
# It includes Nginx (with SSL), WordPress, and MySQL.
# It is designed to be robust and avoid common race conditions.
#
# Usage: ./setup-wordpress.sh
#

# Stop on any error
set -e

# === CONFIGURATION ===
# You can change these variables if you want.
DOMAIN_NAME="amirrezakzm.ir"
PROJECT_DIR_NAME="wordpress-stack"
NETWORK_NAME="wp_net"
DB_VOLUME="wp_db_data"
WP_VOLUME="wp_files_data"

# Generate a secure, random password for the database
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
MYSQL_PASSWORD=$(openssl rand -base64 32)
MYSQL_DATABASE="wordpress"
MYSQL_USER="wordpress"

# === STEP 1: CLEANUP PREVIOUS ENVIRONMENT ===
echo "--- Step 1: Cleaning up any previous environment... ---"
# Stop and remove containers, ignoring errors if they don't exist
docker stop nginx wordpress mysql &> /dev/null || true
docker rm nginx wordpress mysql &> /dev/null || true

# Remove old project directory to ensure a clean slate
if [ -d "./${PROJECT_DIR_NAME}" ]; then
	  echo "Removing old project directory: ./${PROJECT_DIR_NAME}"
	    rm -rf "./${PROJECT_DIR_NAME}"
fi
echo "Cleanup complete."
echo

# === STEP 2: SETUP HOST ENVIRONMENT ===
echo "--- Step 2: Setting up host environment... ---"
mkdir -p "./${PROJECT_DIR_NAME}/nginx/conf.d"
mkdir -p "./${PROJECT_DIR_NAME}/nginx/certs"
echo "Project directories created in ./${PROJECT_DIR_NAME}"
echo
echo "IMPORTANT: Make sure this line is in your /etc/hosts file:"
echo "127.0.0.1   ${DOMAIN_NAME}"
echo
sleep 3

# === STEP 3: CREATE DOCKER RESOURCES ===
echo "--- Step 3: Creating Docker network and volumes... ---"
docker network create "${NETWORK_NAME}"
docker volume create "${DB_VOLUME}"
docker volume create "${WP_VOLUME}"
echo "Network and volumes created."
echo

# === STEP 4: GENERATE SELF-SIGNED SSL CERTIFICATE ===
echo "--- Step 4: Generating self-signed SSL certificate... ---"
openssl req -x509 -nodes -newkey rsa:4096 -days 365 \
	  -keyout "./${PROJECT_DIR_NAME}/nginx/certs/key.pem" \
	    -out "./${PROJECT_DIR_NAME}/nginx/certs/cert.pem" \
	      -subj "/C=IR/ST=Tehran/L=Tehran/O=DockerMe/CN=${DOMAIN_NAME}"
echo "SSL certificate and key generated."
echo

# === STEP 5: CREATE NGINX CONFIGURATION ===
echo "--- Step 5: Creating Nginx configuration file... ---"
# Using a heredoc to write the config file
cat <<EOF > "./${PROJECT_DIR_NAME}/nginx/conf.d/wordpress.conf"
server {
    listen 80;
    server_name ${DOMAIN_NAME};
    return 301 https://\$host\$request_uri;
}

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
    ssl_stapling on;
    ssl_stapling_verify on;

    # HSTS Header (optional, but good for security)
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    location / {
        proxy_pass http://wordpress:80;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
echo "Nginx config written to ./${PROJECT_DIR_NAME}/nginx/conf.d/wordpress.conf"
echo

# === STEP 6: RUN CONTAINERS IN CORRECT ORDER ===
echo "--- Step 6: Launching containers... ---"
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

# This loop is CRITICAL. It waits for MySQL to be fully ready.
echo "Waiting for MySQL to be ready..."
while ! docker logs mysql 2>&1 | grep -q "mysqld: ready for connections."; do
	    sleep 2
    done
    echo "MySQL is ready!"

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
echo "All containers are running."
echo

# === STEP 7: FINAL VERIFICATION ===
echo "--- Step 7: Verifying the setup... ---"
# Give Nginx a moment to start
sleep 5
echo "Pinging ${DOMAIN_NAME}. You should see a 200 OK response."
echo "--------------------------------------------------------"
curl --head --location --insecure "https://${DOMAIN_NAME}"
echo "--------------------------------------------------------"
echo
echo "✅ Setup Complete! You should now be able to access https://${DOMAIN_NAME} in your browser."
