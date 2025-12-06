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
