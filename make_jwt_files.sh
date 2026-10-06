#!/usr/bin/env bash
(
umask 077
d=$(date +%F)
key=$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null)
pub=$(printf '%s\n' "$key" | openssl pkey -pubout)
token=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)
cat > env_files/jwt.env <<EOF
# JWT verification settings (generated $d).
# Loaded by drupal, fcrepo and milliner, the only services that verify Islandora JWTs.
# The 7.x scyllaridae services (houdini, homarus, hypercube, crayfits, mergepdf) don't verify
# JWTs without a jwksUri, so they don't need this.  Contains the admin token: keep out of git.

JWT_ADMIN_TOKEN=$token
JWT_PUBLIC_KEY='$pub'
EOF
cat > env_files/jwt_private.env <<EOF
# JWT signing key (generated $d).  Loaded by drupal only.  Keep out of git.

JWT_PRIVATE_KEY='$key'
EOF
)
