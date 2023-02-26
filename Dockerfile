FROM php:8.1-apache

# opencontainers annotations https://github.com/opencontainers/image-spec/blob/master/annotations.md
LABEL org.opencontainers.image.authors="Stockifi <setup@stockifi.io>" \
      org.opencontainers.image.title="OfficeLife." \
      org.opencontainers.image.description="Know how your employees feel." \
      org.opencontainers.image.url="https://officelife.io" \
      org.opencontainers.image.source="https://github.com/officelifehq/docker" \
      org.opencontainers.image.vendor="OfficeLife"

# entrypoint.sh dependencies
RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash \
        busybox-static \
    ; \
    rm -rf /var/lib/apt/lists/*

# Install required PHP extensions
RUN set -ex; \
    \
    savedAptMark="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libicu-dev \
        zlib1g-dev \
        libzip-dev \
        libpq-dev \
        libsqlite3-dev \
        libxml2-dev \
        libfreetype6-dev \
        libmemcached-dev \
    ; \
    \
    debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
    docker-php-ext-configure intl; \
    docker =-php-ext-configure pgsql -with-pgsql=/usr/local/pgsql; \
    docker-php-ext-install -j$(nproc) \
        intl \
        zip \
        pdo \
        pdo_mysql \
        mysqli \
        pdo_pgsql \
        pgsql \
        pdo_sqlite \
    ; \
    \
# pecl will claim success even if one install fails, so we need to perform each install separately
    pecl install APCu-5.1.20; \
    pecl install memcached-3.1.5; \
    pecl install redis-5.3.4; \
    \
    docker-php-ext-enable \
        apcu \
        memcached \
        redis \
    ; \
    \
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
        ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { print $3 }' \
        | sort -u \
        | xargs -r dpkg-query -S \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
        \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

# Set crontab for schedules
RUN set -ex; \
    \
    mkdir -p /var/spool/cron/crontabs; \
    rm -f /var/spool/cron/crontabs/root; \
    echo '*/5 * * * * php /var/www/html/artisan schedule:run -v' > /var/spool/cron/crontabs/www-data

# Opcache
ENV PHP_OPCACHE_VALIDATE_TIMESTAMPS="0" \
    PHP_OPCACHE_MAX_ACCELERATED_FILES="20000" \
    PHP_OPCACHE_MEMORY_CONSUMPTION="192" \
    PHP_OPCACHE_MAX_WASTED_PERCENTAGE="10"
RUN set -ex; \
    \
    docker-php-ext-enable opcache; \
    { \
        echo '[opcache]'; \
        echo 'opcache.enable=1'; \
        echo 'opcache.revalidate_freq=0'; \
        echo 'opcache.validate_timestamps=${PHP_OPCACHE_VALIDATE_TIMESTAMPS}'; \
        echo 'opcache.max_accelerated_files=${PHP_OPCACHE_MAX_ACCELERATED_FILES}'; \
        echo 'opcache.memory_consumption=${PHP_OPCACHE_MEMORY_CONSUMPTION}'; \
        echo 'opcache.max_wasted_percentage=${PHP_OPCACHE_MAX_WASTED_PERCENTAGE}'; \
        echo 'opcache.interned_strings_buffer=16'; \
        echo 'opcache.fast_shutdown=1'; \
    } > $PHP_INI_DIR/conf.d/opcache-recommended.ini; \
    \
    echo 'apc.enable_cli=1' >> $PHP_INI_DIR/conf.d/docker-php-ext-apcu.ini; \
    \
    echo 'memory_limit=512M' > $PHP_INI_DIR/conf.d/memory-limit.ini

RUN set -ex; \
    \
    a2enmod headers rewrite remoteip; \
    { \
        echo RemoteIPHeader X-Real-IP; \
        echo RemoteIPTrustedProxy 10.0.0.0/8; \
        echo RemoteIPTrustedProxy 172.16.0.0/12; \
        echo RemoteIPTrustedProxy 192.168.0.0/16; \
    } > $APACHE_CONFDIR/conf-available/remoteip.conf; \
    a2enconf remoteip

RUN set -ex; \
    APACHE_DOCUMENT_ROOT=/var/www/html/public; \
    sed -ri -e "s!/var/www/html!${APACHE_DOCUMENT_ROOT}!g" $APACHE_CONFDIR/sites-available/*.conf; \
    sed -ri -e "s!/var/www/!${APACHE_DOCUMENT_ROOT}!g" $APACHE_CONFDIR/apache2.conf $APACHE_CONFDIR/conf-available/*.conf

WORKDIR /var/www/html

# Define OfficeLife version
ENV OFFICELIFE_VERSION main
LABEL org.opencontainers.image.revision="" \
      org.opencontainers.image.version="main"
COPY . /var/www/html

ARG DB_CONNECTION
ARG DB_HOST
ARG DB_PORT
ARG DB_DATABASE
ARG DB_USERNAME
ARG DB_PASSWORD
ARG APP_URL
ENV DB_CONNECTION=$DB_CONNECTION \
    DB_HOST=$DB_HOST \
    DB_PORT=$DB_PORT \
    DB_DATABASE=$DB_DATABASE \
    DB_USERNAME=$DB_USERNAME \
    DB_PASSWORD=$DB_PASSWORD \
    APP_URL=${APP_URL}

RUN set -ex; \
    fetchDeps=" \
        gnupg \
    "; \
    apt-get update; \
    apt-get install -y --no-install-recommends $fetchDeps; \
    \
    sed -e ' \
        s/APP_ENV=.*/APP_ENV=production/; \
        s/APP_DEBUG=.*/APP_DEBUG=false/; \
        s/APP_URL=.*/APP_URL=${APP_URL}/; \
        s/LOG_CHANNEL=.*/LOG_CHANNEL=errorlog/; \
        s/DB_CONNECTION=.*/DB_CONNECTION=${DB_CONNECTION}/; \
        s/DB_DATABASE=.*/DB_DATABASE=${DB_DATABASE}/; \
        s/DB_HOST=.*/DB_HOST=${DB_HOST}/; \
        s/DB_PORT=.*/DB_PORT=${DB_PORT}/; \
        s/DB_USERNAME=.*/DB_USERNAME=${DB_USERNAME}/; \
        s/DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/; \
        ' \
        /var/www/html/.env.example > /var/www/html/.env; \
    \
    chown -R www-data:www-data /var/www/html; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $fetchDeps; \
    rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh \
    docker/queue.sh \
    docker/cron.sh \
    /usr/local/bin/

# change access permission for entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# expose port 80
EXPOSE 80
CMD ["apache2-foreground"]
