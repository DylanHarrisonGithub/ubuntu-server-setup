#!/bin/bash



################################################################ INFO ################################################################
echo
echo
echo "################ INFO ################"
echo "This script installs and configures packages needed to run a node/postgresql application on a fresh Ubuntu 20.x install"
echo "Ensure that this script is run with sudo privileges sudo ./server-setup.sh"
echo
echo "packages installed:"
echo " * node & npm"
echo " * pm2"
echo " * nginx"
echo " * postgresql"
echo " * certbot"
echo
echo "please have the following information prepared:"
echo " * choose a database username"
echo " * choose a database password"
echo " * choose a database project"
echo " * have a registered domain name"
echo " * choose a name for your web app"
echo " * choose a port for your web app"
echo " * have a google email address for node mailer that is set up with 2 factor authentication"
echo " * set up an app password for the nodemailer email and have it ready"
echo " * an admin email address that will receive emails addressed to admin (can be same as node mailer email)"
echo " * a maximum vps hard drive capacity in gigabytes"
echo " * a github repo url for your node web application"
echo " * a github private access token for the app if it is private"
echo
read -p "Are you ready to proceed? (yes/no): " response
if [[ "$response" != "yes" ]]; then
  echo "Terminating script."
  exit 1
fi




################################################################ SERVER ################################################################
echo
echo
echo "################ UBUNTU SETUP.. ################"

# Update package lists and upgrade installed packages
echo
echo "Initializing server and updating server.."
sudo apt update
sudo apt upgrade -y




################################################################ NODE AND NPM ################################################################
echo
echo
echo "################ NODE AND NPM SETUP.. ################"

# node latest stable and npm
echo
echo "Installing latest stable version of node and npm"
sudo snap install node --classic




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

# Prompt for new PostgreSQL user details
echo
read -p "Enter new PostgreSQL username: " dbusername
read -s -p "Enter password for $dbusername: " dbpassword # should the password be randomly generated instead?
read -p "Enter name for the new database: " dbname

# Connect to PostgreSQL and execute SQL commands
echo
sudo -u postgres psql -c "CREATE DATABASE $dbname;"
sudo -u postgres psql -c "CREATE USER $dbusername WITH PASSWORD '$dbpassword';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $dbname TO $dbusername;"

echo "PostgreSQL database '$dbname' and user '$dbusername' with all privileges successfully created."

read -p "Would you like to allow remote connections for $dbusername? (yes/no): " response
if [[ "$response" == "yes" ]]; then


    # Define the directory path
    pgdirectory="/etc/postgresql"

    # Use find to list directories (excluding '.' and '..'), limit to first result, and extract directory name
    first_directory=$(find "$pgdirectory" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | head -n 1)

    pg_hba_conf="/etc/postgresql/$first_directory/main/pg_hba.conf"
    postgresql_conf="/etc/postgresql/$fisrt_directory/main/postgresql.conf"

    echo "Modifying pg_hba.conf..."
    # Append new rule to allow remote connection for $dbusername
    echo "host    $database   $dbusername   $remote_ip   md5" >> $pg_hba_conf

       echo "Modifying postgresql.conf..."
    # Uncomment or set listen_addresses to '*' to listen on all addresses
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $postgresql_conf

fi



################################################################ ENVIRONMENT VARIABLES ################################################################
echo
echo
echo "################ ENVIRONMENT VARIABLE SETUP.. ################"

LENGTH=64

random_string=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c $LENGTH ; echo '')

read -p "Enter your app name [default: APPNAME]: " appname
appname=${appname:-"APPNAME"}
appname="${appname^^}"             # cast to upper case


# app server secret
echo "${appname}_SERVER_SECRET=\"$random_string\"" | sudo tee -a /etc/environment

# app database connection string DATABASE_URL=postgres://{user}:{password}@{hostname or localhost}:{port}/{database-name}
echo "${appname}_DATABASE_URL=\"postgres://$dbusername:$dbpassword@localhost:5432/$dbname\"" | sudo tee -a /etc/environment

# port
read -p "Enter your app port [default: 3000]: " portnumber
portnumber=${portnumber:-3000}
echo "${appname}_PORT=\"$portnumber\"" | sudo tee -a /etc/environment

# nodemailer
read -p "Enter your app's nodemailer email address: " nodemailer_email
echo "${appname}_NODEMAILER_EMAIL=\"$nodemailer_email\"" | sudo tee -a /etc/environment

read -p "Enter your app's nodemailer email password: " nodemailer_password
echo "${appname}_NODEMAILER_PASSWORD=\"$nodemailer_password\"" | sudo tee -a /etc/environment

# admin email
read -p "Enter your admin's email address: " admin_email
echo "${appname}_ADMIN_EMAIL=\"$admin_email\"" | sudo tee -a /etc/environment

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

read -p "Enter your domain name [default: mydomain.com]: " domain
domain=${domain:-"mydomain.com"}
domain=${domain#https://}
domain=${domain#http://}
domain=${domain#www.}

# Install nginx
echo
echo "Installing nginx"
sudo apt-get install -y nginx

# install certbot
echo
echo "Installing certbot"
sudo snap install certbot --classic

# configure nginx for https with certbot
echo
echo "Obtaining SSL certificate for domain $domain..."
sudo certbot --nginx -d $domain -d www.$domain

# Configure Nginx to proxy requests to your Node.js application on port 3000
echo "Configuring Nginx..."
sudo tee "/etc/nginx/sites-available/default" > /dev/null <<EOF
server {
   listen 443 ssl;
   server_name $domain www.$domain;

   ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

   # SSL configuration
   # Include SSL settings like protocols, ciphers, etc. as needed

   location / {
       proxy_pass http://localhost:$app_port;
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

   # Additional configurations can be added as needed
}

EOF

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

