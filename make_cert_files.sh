#!/usr/bin/env bash
# Creates the development TLS files in ./dev_certs that docker-compose.yml and traefik use:
#   rootCA.pem, rootCA-key.pem  local certificate authority (reused if already present)
#   cert.pem, privkey.pem       *.islandora.dev certificate signed by that CA
#   UID                         host user id, passed to drupal as a secret
# Import rootCA.pem into your browser / OS trust store to avoid certificate warnings.
set -euo pipefail

cd "$(dirname "$0")"
dir=dev_certs
mkdir -p "$dir"
cd "$dir"
umask 077

names=(islandora.dev '*.islandora.dev' islandora.io '*.islandora.io' islandora.info '*.islandora.info' localhost)
ips=(127.0.0.1 ::1)

if [[ -e rootCA.pem || -e rootCA-key.pem ]]; then
    if [[ ! -r rootCA.pem || ! -r rootCA-key.pem ]]; then
        echo "$dir/rootCA.pem or $dir/rootCA-key.pem exists but is not readable by $(id -un)." >&2
        echo "Fix with: sudo chown $(id -u):$(id -g) $dir/*.pem   (or delete both to make a new CA)" >&2
        exit 1
    fi
    echo "Reusing existing CA in $dir/rootCA.pem"
else
    echo "Creating new CA in $dir/rootCA.pem"
    openssl genpkey -quiet -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out rootCA-key.pem
    openssl req -x509 -new -key rootCA-key.pem -sha256 -days 3650 -out rootCA.pem \
        -subj "/O=Islandora development CA/OU=$(id -un)@$(hostname)/CN=Islandora dev CA $(id -un)@$(hostname)" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,keyCertSign,cRLSign"
fi

san=""
for n in "${names[@]}"; do san+="DNS:$n,"; done
for i in "${ips[@]}"; do san+="IP:$i,"; done
san=${san%,}

ext=$(mktemp)
trap 'rm -f "$ext" cert.csr' EXIT
cat > "$ext" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=$san
EOF

echo "Creating $dir/cert.pem and $dir/privkey.pem"
openssl genpkey -quiet -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out privkey.pem
openssl req -new -key privkey.pem -sha256 -out cert.csr \
    -subj "/O=Islandora development certificate/CN=islandora.dev"
# 825 days is the longest validity macOS/iOS accept for TLS server certs.
openssl x509 -req -in cert.csr -CA rootCA.pem -CAkey rootCA-key.pem -CAcreateserial \
    -sha256 -days 825 -extfile "$ext" -out cert.pem 2>/dev/null
rm -f rootCA.srl

printf '%s' "$(id -u)" > UID

# Public files must be readable inside containers; keys stay owner-only.
chmod 644 cert.pem rootCA.pem UID
chmod 600 privkey.pem rootCA-key.pem

openssl verify -CAfile rootCA.pem cert.pem
