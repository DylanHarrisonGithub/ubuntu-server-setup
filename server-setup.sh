#!/bin/bash



################################################################ INFO ################################################################
echo
echo
echo "################ INFO ################"
echo "This script installs and configures packages needed to run a node/postgresql application on a fresh Ubuntu 20.x install"
echo "Ensure that this script is run with sudo privileges sudo ./server-setup.sh"
echo "Ensure that you have registered a domain name and created an A-record assosicating with the static ip of this server"
echo
echo "packages installed:"
echo " * node & npm"
echo " * pm2"
echo " * nginx"
echo " * postgresql"
echo " * certbot"
echo
echo "please have the following information prepared:"
echo " * a name for your web app"
echo " * a port for your web app"
echo " * a registered domain name with A Record for this server's i.p."
echo " * a google gmail admin's email address with 2 factor authentication enabled"
echo " * an app password for the gmail account"
echo " * a maximum vps hard drive capacity in gigabytes"
echo " * a github repository url for your node web application"
echo " * a github private access token for the repository if it is private"
echo
read -p "Are you ready to proceed? (yes/no): " response
if [[ "$response" != "yes" ]]; then
  echo "Terminating script."
  exit 1
fi




################################################################ ENVIRONMENT VARIABLES ################################################################
echo
echo
echo "################ ENVIRONMENT VARIABLE SETUP.. ################"

# app name
read -p "Enter your app name [default: MYAPP]: " appname
appname=${appname:-"MYAPP"}
appname="${appname^^}"             # cast to upper case


# port
read -p "Enter your app port [default: 3000]: " portnumber
portnumber=${portnumber:-3000}
echo "${appname}_PORT=\"$portnumber\"" | sudo tee -a /etc/environment


# domain
read -p "Enter your domain name [default: mydomain.com]: " domain
domain=${domain:-"mydomain.com"}
domain=${domain#https://}
domain=${domain#http://}
domain=${domain#www.}

# app server secret
LENGTH=64
random_string=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c $LENGTH ; echo '')
echo "${appname}_SERVER_SECRET=\"$random_string\"" | sudo tee -a /etc/environment


# db dbname dbusername dbpassword
LENGTH_DB_PWD=16
dbpassword=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c $LENGTH_DB_PWD ; echo '')
dbname="${appname,,}db"
dbusername="${appname,,}"


# db allow remote connections
read -p "Would you like to allow remote database connections on port 5432 (yes/no): " dballowremote


# app database connection string DATABASE_URL=postgres://{user}:{password}@{hostname or localhost}:{port}/{database-name}
echo "${appname}_DATABASE_URL=\"postgres://$dbusername:$dbpassword@localhost:5432/$dbname\"" | sudo tee -a /etc/environment


# admin email
read -p "Enter your admin's gmail address: " admin_email
echo "${appname}_ADMIN_EMAIL=\"$admin_email\"" | sudo tee -a /etc/environment


# nodemailer
echo "${appname}_NODEMAILER_EMAIL=\"$admin_email\"" | sudo tee -a /etc/environment


# nodemailer app password
read -p "Enter your gmail app password: " nodemailer_password
echo "${appname}_NODEMAILER_PASSWORD=\"$nodemailer_password\"" | sudo tee -a /etc/environment


# max server hd size
read -p "Enter your server's max hard drive capacity in gigabytes [default: 30]: " hd_size
hd_size=${hd_size:-30}
echo "${appname}_MAX_HD_SIZE_GB=\"$hd_size\"" | sudo tee -a /etc/environment

# app github repo
read -p "Enter your application's github repo address: " repo_url
# sanitize input
repo_url=${repo_url#https://}
repo_url=${repo_url#http://}
repo_url=${repo_url#www.}
echo "${appname}_REPO_URL=\"$repo_url\"" | sudo tee -a /etc/environment

read -p "Enter your application's github repo private access token: " repo_pat
echo "${appname}_REPO_PAT=\"$repo_pat\"" | sudo tee -a /etc/environment





################################################################ SERVER ################################################################
echo
echo
echo "################ UBUNTU SETUP.. ################"

# Update package lists and upgrade installed packages
echo
echo "Initializing server and updating server.."
sudo apt update
sudo apt upgrade -y          # is this causing problems?
sudo snap refresh




################################################################ NODE AND NPM ################################################################
echo
echo
echo "################ NODE AND NPM SETUP.. ################"

# installing node and npm
echo
echo "Installing latest stable version of node and npm"
# sudo snap install node --classic    # BROKEN
curl -sL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs




################################################################ PM2 ################################################################
echo
echo
echo "################ PM2 SETUP ################"
# pm2
echo
echo "Installing pm2"
sudo npm install pm2 -g




################################################################ POSTGRESQL ################################################################
echo
echo
echo "################ POSTGRESQL SETUP.. ################"

# Install PostgreSQL
echo
echo "installing PostgreSQL"
sudo apt-get install -y postgresql postgresql-contrib

# ensure postgresql starts automatically at boot
sudo systemctl enable postgresql


# Connect to PostgreSQL and execute SQL commands
echo
sudo -u postgres psql -c "CREATE DATABASE $dbname;"
sudo -u postgres psql -c "CREATE USER $dbusername WITH PASSWORD '$dbpassword';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $dbname TO $dbusername;"


# Retrieve PostgreSQL version
postgres_version=$(psql -U postgres -tAc "SELECT current_setting('server_version_num');")

# Compare PostgreSQL version
if [ "$postgres_version" -ge 150000 ]; then
    echo "PostgreSQL version is 15 or greater."
    # Grant privileges using psql command
    psql -U postgres -c "GRANT ALL ON SCHEMA public TO $dbusername;" $dbname
else
    echo "PostgreSQL version is less than 15."
    # Handle for older versions if needed
fi


echo "PostgreSQL database '$dbname' and user '$dbusername' with all privileges successfully created."

# configure allow remote connections
if [[ "$dballowremote" == "yes" ]]; then

    # Variable to store the found directory
    FOUND_DIR=""

    # Check each directory under /etc/postgresql
    for conf_dir in /etc/postgresql/*; do
        if [ -d "$conf_dir" ]; then
            echo "directory $conf_dir found in /etc/postgresql"
            if [ -f "$conf_dir/main/pg_hba.conf" ] && [ -f "$conf_dir/main/postgresql.conf" ]; then
                echo "Found configuration files in directory: $conf_dir"
                FOUND_DIR="$conf_dir"
                break  # Exit the loop once the directory is found
            fi
        fi
    done

    # Check if a directory was found
    if [ -n "$FOUND_DIR" ]; then

        pg_hba_conf="$FOUND_DIR/main/pg_hba.conf"
        postgresql_conf="$FOUND_DIR/main/postgresql.conf"

        echo "Modifying pg_hba.conf..."
        # Append new rule to allow remote connection for $dbusername
        echo "host    $dbname   $dbusername   0.0.0.0/0   md5" >> $pg_hba_conf

        echo "Modifying postgresql.conf..."
        # Uncomment or set listen_addresses to '*' to listen on all addresses
        sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $postgresql_conf

        echo "Postgres successfully modified to allow remote connections"
        echo "Please ensure that port 5432 is open on your server firewall"

    else
        echo "Error: PostgreSQL configuration directory not found under /etc/postgresql"
        echo "PostgreSQL could not be configured to allow remote access"
    fi


fi




################################################################ APP SETUP ################################################################
echo
echo
echo "################ APP SETUP.. ################"
# Check if repo_url is not empty
if [ -n "$repo_url" ]; then

  if [ -n "$repo_pat" ]; then
    git clone "https://$repo_pat@$repo_url"
  else
    git clone "$repo_url"
  fi

  # Extract repository name from repo_url
  repo_name=$(basename "$repo_url" .git)

  # Change to the repository directory
  cd "$repo_name"

  # Check if package.json exists (assuming npm project)
  if [ -f package.json ]; then
      # Install npm packages
      npm install
  else
      echo "No package.json found. Skipping npm install."
  fi
else
    echo "repo_url is empty. Skipping clone. You will have to manually install your app."
fi




################################################################ NGINX ################################################################
echo
echo
echo "################ NGINX & CERTBOT SETUP.. ################"

# Install nginx
echo
echo "Installing nginx"
sudo apt-get install -y nginx

# Configure Nginx to proxy requests to your Node.js application on app port
echo "Configuring Nginx..."

# Define variables
NGINX_CONF_FILE="/etc/nginx/sites-available/default"
DOMAIN="$domain www.$domain"

# Check if Nginx configuration file exists
if [ ! -f "$NGINX_CONF_FILE" ]; then
    echo "Nginx configuration file '$NGINX_CONF_FILE' not found."
    exit 1
fi

nginx_default_config=$(cat << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    server_name $domain www.$domain;

    location / {
       proxy_pass http://localhost:$portnumber;
       client_max_body_size 5G;
       proxy_http_version 1.1;
       proxy_set_header Host \$host;
       proxy_set_header X-Real-IP \$remote_addr;
       proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto https;
       proxy_set_header Upgrade \$http_upgrade;
       proxy_set_header Connection 'upgrade';
       proxy_cache_bypass \$http_upgrade;
    }
}
EOF
)

# Overwrite nginx default configuration file
sudo bash -c "echo '$nginx_default_config' > /etc/nginx/sites-available/default"

# Reload nginx configuration to apply changes
sudo systemctl reload nginx

# Check NGINX config
sudo nginx -t

# # Restart NGINX
# sudo service nginx restart

# install certbot
echo
echo "Installing certbot"
sudo snap install certbot --classic

# configure nginx for https with certbot
echo
echo "Obtaining SSL certificate for domain $domain..."
sudo certbot --nginx -d $domain -d www.$domain --agree-tos --register-unsafely-without-email -n

# Test Nginx configuration and reload
echo "Testing Nginx configuration..."
sudo nginx -t

if [ $? -eq 0 ]; then
    echo "Reloading Nginx..."
    sudo systemctl reload nginx
    echo "Nginx configuration updated successfully."
else
    echo "Error: Nginx configuration test failed. Please check configuration."
fi

# test certbot renewal
echo
echo "Testing certbot auto-renewal"
sudo certbot renew --dry-run



################################################################ COMPLETE ################################################################
echo
echo "################ COMPLETE ################"
echo "Server setup is complete."
echo "System reset is now required."
echo "After reset, navigate to app folder and run:"
echo "sudo pm2 start index.js"
echo

