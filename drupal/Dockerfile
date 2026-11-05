# syntax=docker/dockerfile:1.27.0@sha256:bde3983e9c939224420ddaf6b784cc30e09b035a4dea01f581230c50809f372e
ARG REPOSITORY
ARG TAG
FROM ${REPOSITORY}/drupal:${TAG}

ARG TARGETARCH

COPY --link rootfs /

RUN --mount=type=cache,id=custom-drupal-composer-${TARGETARCH},sharing=locked,target=/root/.composer/cache \
    composer install -d /var/www/drupal && \
    composer require -d /var/www/drupal \
        'drupal/islandora_dxpr:^1.0@beta' \
        && \
    composer outdated -d /var/www/drupal 'drupal/*' || true && \
    composer update -d /var/www/drupal 'drupal/*' --with-all-dependencies && \
    chown -R nginx:nginx /var/www/drupal && \
    cleanup.sh
