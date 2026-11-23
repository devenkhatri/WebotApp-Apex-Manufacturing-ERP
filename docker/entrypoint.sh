#!/usr/bin/env bash
set -e

echo "==> Apex ERP Container Initializing..."

# Ensure storage and bootstrap/cache directories exist
mkdir -p /var/www/html/storage/framework/sessions \
         /var/www/html/storage/framework/views \
         /var/www/html/storage/framework/cache/data \
         /var/www/html/storage/logs \
         /var/www/html/bootstrap/cache

# Ensure write permissions
chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache
chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache 2>/dev/null || true

# Clear any cached packages/services from host mount
rm -f /var/www/html/bootstrap/cache/packages.php \
      /var/www/html/bootstrap/cache/services.php \
      /var/www/html/bootstrap/cache/config.php

# Prepare environment file if absent
if [ ! -f /var/www/html/.env ]; then
    if [ -f /var/www/html/.env.docker.example ]; then
        echo "==> Creating .env from .env.docker.example..."
        cp /var/www/html/.env.docker.example /var/www/html/.env
    elif [ -f /var/www/html/.env.example ]; then
        echo "==> Creating .env from .env.example..."
        cp /var/www/html/.env.example /var/www/html/.env
    fi
fi

# Ensure composer dependencies exist
if [ ! -f /var/www/html/vendor/autoload.php ]; then
    echo "==> Vendor directory missing. Running composer install..."
    composer install --no-interaction --prefer-dist --optimize-autoloader
fi

# Generate application key if not set
if ! grep -q "^APP_KEY=base64:" /var/www/html/.env 2>/dev/null; then
    echo "==> Generating application key..."
    php artisan key:generate --force
fi

# Ensure container process uses the valid key from .env
LOADED_KEY=$(grep -E "^APP_KEY=base64:" /var/www/html/.env 2>/dev/null | head -n 1 | cut -d '=' -f2-)
if [ -n "$LOADED_KEY" ]; then
    export APP_KEY="$LOADED_KEY"
fi

# Wait for database if DB_CONNECTION=mysql and DB_HOST is set
if [ "$DB_CONNECTION" = "mysql" ] && [ -n "$DB_HOST" ]; then
    echo "==> Checking database readiness at $DB_HOST:${DB_PORT:-3306}..."
    max_retries=30
    count=0
    until php -r "try { new PDO('mysql:host='.getenv('DB_HOST').';port='.(getenv('DB_PORT') ?: 3306), getenv('DB_USERNAME'), getenv('DB_PASSWORD')); exit(0); } catch (Exception \$e) { exit(1); }" 2>/dev/null; do
        count=$((count + 1))
        if [ $count -ge $max_retries ]; then
            echo "==> Warning: Database connection timed out after $max_retries attempts. Continuing..."
            break
        fi
        sleep 1
    done
    echo "==> Database is reachable."
fi

# Run database migrations if AUTORUN_MIGRATIONS is true
if [ "${AUTORUN_MIGRATIONS:-false}" = "true" ]; then
    echo "==> Running database migrations..."
    php artisan migrate --force
fi

echo "==> Initialization complete. Starting service..."
exec "$@"
