ARG TAG=7.0.27
FROM islandora/milliner:${TAG}

# Upgrade PHP-FPM, the CLI, and the installed PHP extensions together.
RUN apk info | grep '^php84-' | xargs apk add --no-cache --upgrade 'php84>=8.4.28' && \
    php -r 'exit(version_compare(PHP_VERSION, "8.4.28", "<") ? 1 : 0);' && \
    php-fpm84 -v | grep -F "PHP $(php -r 'echo PHP_VERSION;') "
