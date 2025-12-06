#!/bin/bash
set -e

echo "✅ Setting up Apache virtual host for Laravel"

APACHE_CONF="/etc/apache2/sites-available/laravel.conf"

# Remove old config if exists
sudo rm -f "$APACHE_CONF"

# Create new virtual host
sudo bash -c "cat > $APACHE_CONF <<'EOF'
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
EOF"

# Disable default Apache site and enable Laravel site
sudo a2dissite 000-default.conf || true
sudo a2ensite laravel.conf

# Reload Apache to apply changes
sudo systemctl reload apache2

echo "✅ Apache virtual host setup completed"
cd /var/www/backend

echo "✅ Ensure .env exists"
if [ ! -f .env ]; then
  cp .env.example .env
fi

# Ensure APP_KEY exists
php artisan key:generate --force || true

# Clear and cache configs
php artisan config:clear
php artisan cache:clear
php artisan route:clear
php artisan view:clear
php artisan config:cache

# Create cache table if CACHE_DRIVER=database
php artisan cache:table || true
php artisan migrate --force

echo "✅ Laravel database and cache setup complete"
