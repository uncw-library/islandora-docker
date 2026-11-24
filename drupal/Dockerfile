# syntax=docker/dockerfile:1.27.0@sha256:bde3983e9c939224420ddaf6b784cc30e09b035a4dea01f581230c50809f372e
ARG REPOSITORY
ARG TAG
FROM ${REPOSITORY}/drupal:${TAG}

ARG TARGETARCH

# Upgrade the PHP runtime and every installed PHP 8.4 extension together.
RUN apk info | grep '^php84-' | xargs apk add --no-cache --upgrade 'php84>=8.4.28' && \
    php -r 'exit(version_compare(PHP_VERSION, "8.4.28", "<") ? 1 : 0);' && \
    php-fpm84 -v | grep -F "PHP $(php -r 'echo PHP_VERSION;') "

COPY --link rootfs /
COPY --link themes/uncw_barrio /var/www/drupal/web/themes/custom/uncw_barrio

RUN --mount=type=cache,id=custom-drupal-composer-${TARGETARCH},sharing=locked,target=/root/.composer/cache \
    # No composer.lock: install resolves the newest versions allowed by composer.json. check composer.json advisories and patches if seeing errors.
    composer install -d /var/www/drupal && \
    chown -R nginx:nginx /var/www/drupal && \
    cleanup.sh
