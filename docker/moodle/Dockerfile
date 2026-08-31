ARG PHP_VERSION=8.3
FROM php:${PHP_VERSION}-apache

# System libraries needed to build the PHP extensions Moodle requires
# https://docs.moodle.org/500/en/PHP
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libzip-dev \
        libicu-dev \
        libxml2-dev \
        libxslt1-dev \
        libonig-dev \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" \
        curl \
        mbstring \
        mysqli \
        pdo_mysql \
        gd \
        intl \
        zip \
        soap \
        exif \
        xsl \
        opcache

RUN a2enmod rewrite

# Since Moodle 5.0 the web-servable files live under public/, while the
# checkout root (config.php, admin/cli/*, lib/) stays outside the docroot.
# https://docs.moodle.org/500/en/Installing_Moodle#Public_directory
RUN sed -ri -e 's!/var/www/html!/var/www/html/public!g' \
        /etc/apache2/sites-available/*.conf \
        /etc/apache2/apache2.conf \
        /etc/apache2/conf-available/*.conf

COPY php-moodle.ini /usr/local/etc/php/conf.d/zz-moodle.ini

WORKDIR /var/www/html
