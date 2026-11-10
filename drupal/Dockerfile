# syntax=docker/dockerfile:1.27.0@sha256:bde3983e9c939224420ddaf6b784cc30e09b035a4dea01f581230c50809f372e
ARG REPOSITORY
ARG TAG
FROM ${REPOSITORY}/drupal:${TAG}

ARG TARGETARCH

COPY --link rootfs /
COPY --link themes/uncw_barrio /var/www/drupal/web/themes/custom/uncw_barrio

RUN --mount=type=cache,id=custom-drupal-composer-${TARGETARCH},sharing=locked,target=/root/.composer/cache \
    composer install -d /var/www/drupal && \
    composer require -d /var/www/drupal \
        'drupal/islandora_dxpr:^1.0@beta' \
        'born-digital/ip_range_access:^1.0' \
        'drupal/bootstrap_barrio:^5.5' \
        && \
    # ip_range_access declares core ^9 || ^10 only; allow Drupal 11
    sed -i 's/^core_version_requirement:.*/core_version_requirement: ^9 || ^10 || ^11/' \
        /var/www/drupal/web/modules/contrib/ip_range_access/ip_range_access.info.yml && \
    composer outdated -d /var/www/drupal 'drupal/*' || true && \
    composer update -d /var/www/drupal 'drupal/*' --with-all-dependencies && \
    chown -R nginx:nginx /var/www/drupal && \
    cleanup.sh
