#!/bin/bash
set -e

cd /var/www/backend

echo "✅ Set AWS region"
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1

echo "✅ Install Apache + PHP 8.2 (mod_php) and dependencies"
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:ondrej/php
sudo apt update

sudo apt install -y \
  apache2 \
  php8.2 libapache2-mod-php8.2 \
  php8.2-cli php8.2-common \
  php8.2-mysql php8.2-zip php8.2-gd \
  php8.2-mbstring php8.2-curl \
  php8.2-xml php8.2-bcmath php8.2-intl \
  jq

echo "✅ Enable Apache rewrite module"
sudo a2enmod rewrite

echo "✅ Configure Apache virtual host for Laravel"
sudo tee /etc/apache2/sites-available/000-default.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/backend/public

    <Directory /var/www/backend/public>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/laravel_error.log
    CustomLog \${APACHE_LOG_DIR}/laravel_access.log combined
</VirtualHost>
EOF

echo "✅ Reload Apache"
sudo systemctl restart apache2

echo "✅ Install Composer dependencies"
export COMPOSER_ALLOW_SUPERUSER=1
composer install --no-dev --optimize-autoloader --no-interaction

# --- RDS Credentials ---
echo "✅ Fetch RDS credentials from environment variables"
# Make sure GitHub Actions passes BACKEND_HOST and RDS_ENDPOINT as env
if [ -z "$BACKEND_HOST" ] || [ -z "$RDS_ENDPOINT" ]; then
  echo "❌ BACKEND_HOST or RDS_ENDPOINT not set"
  exit 1
fi

RDS_CREDS=$(aws secretsmanager get-secret-value \
  --secret-id task/rds/creds \
  --query SecretString \
  --output text)

DB_USER=$(echo "$RDS_CREDS" | jq -r .username)
DB_PASS=$(echo "$RDS_CREDS" | jq -r .password)

# --- Setup .env ---
echo "✅ Prepare .env"
if [ ! -f .env ]; then
  cp .env.example .env
fi

sed -i 's/APP_ENV=.*/APP_ENV=production/' .env
sed -i 's/APP_DEBUG=.*/APP_DEBUG=false/' .env
sed -i "s|APP_URL=.*|APP_URL=http://$BACKEND_HOST|" .env

sed -i 's/DB_CONNECTION=.*/DB_CONNECTION=mysql/' .env
sed -i "s|DB_HOST=.*|DB_HOST=$RDS_ENDPOINT|" .env
sed -i 's/DB_PORT=.*/DB_PORT=3306/' .env
sed -i 's/DB_DATABASE=.*/DB_DATABASE=taskdb/' .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=$DB_USER|" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" .env

chmod 600 .env

echo "✅ Ensure APP_KEY exists"
php artisan key:generate --force || true

echo "✅ Ensure cache table exists (for CACHE_DRIVER=database)"
php artisan cache:table || true

echo "⏱ Waiting 5s to ensure DB connection is ready"
sleep 5

echo "✅ Test DB connection"
php -r "new PDO('mysql:host=$RDS_ENDPOINT;dbname=taskdb','$DB_USER','$DB_PASS'); echo 'DB connection OK';"

echo "✅ Run migrations"
php artisan migrate --force

echo "✅ Clear and cache configs"
php artisan config:clear
php artisan cache:clear
php artisan route:clear
php artisan view:clear
php artisan config:cache

echo "✅ Fix permissions"
sudo chown -R www-data:www-data /var/www/backend
sudo chmod -R 755 /var/www/backend
sudo chmod -R 775 /var/www/backend/storage /var/www/backend/bootstrap/cache

echo "✅ Reload Apache"
sudo systemctl reload apache2

echo "🚀 Deployment completed successfully"
