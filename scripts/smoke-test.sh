#!/usr/bin/env bash
# End-to-end smoke test: ingest one image item through Drupal's REST API, then
# confirm every downstream service saw it:
#   drupal -> activemq -> alpaca -> milliner -> fcrepo      (node + binary in Fedora)
#                               -> blazegraph               (triples)
#                               -> houdini                  (service file + thumbnail)
#                               -> crayfits -> fits         (technical metadata)
#   drupal -> solr                                          (search index)
#   browser -> traefik -> cantaloupe -> drupal              (IIIF info.json)
#
# Usage: scripts/smoke-test.sh [--keep]
#   --keep   leave the test item in place (it is also kept if any check fails)
#   TIMEOUT=<seconds> overrides how long to wait for async work (default 180)
set -euo pipefail
cd "$(dirname "$0")/.."

BASE=https://islandora.dev
TIMEOUT=${TIMEOUT:-180}
KEEP=false
[[ "${1:-}" == "--keep" ]] && KEEP=true

CURL=(curl -sS --cacert dev_certs/rootCA.pem)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FAILED=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILED=1; }

sql() { docker exec islandora drush sqlq "$1" | tr -d '\r'; }
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

# Term id for an external URI, so the test doesn't depend on hard-coded tids.
tid() { sql "SELECT entity_id FROM taxonomy_term__field_external_uri WHERE field_external_uri_uri='$1' LIMIT 1"; }

# Retry "$@" until it succeeds or TIMEOUT elapses.
wait_for() {
    local desc=$1; shift
    local end=$((SECONDS + TIMEOUT))
    until "$@" >/dev/null 2>&1; do
        # fail() records the failure; return 0 so set -e lets the remaining checks run.
        if (( SECONDS >= end )); then fail "$desc (timed out after ${TIMEOUT}s)"; return 0; fi
        sleep 3
    done
    pass "$desc ($((SECONDS - start))s)"
}

echo "== Setup"
# Log in as uid 1 with a one-time link so the test doesn't need the admin password,
# then use the session cookie + CSRF token for REST writes.
"${CURL[@]}" -L -c "$TMP/cookies" -b "$TMP/cookies" -o /dev/null \
    "$(docker exec islandora drush user:login --uri="$BASE" --no-browser | tr -d '\r')"
AUTH=(-b "$TMP/cookies" -H "X-CSRF-Token: $("${CURL[@]}" -b "$TMP/cookies" "$BASE/session/token")")
MODEL_IMAGE=$(tid 'http://purl.org/coar/resource_type/c_c513')
USE_ORIGINAL=$(tid 'http://pcdm.org/use#OriginalFile')
USE_SERVICE=$(tid 'http://pcdm.org/use#ServiceFile')
USE_THUMB=$(tid 'http://pcdm.org/use#ThumbnailImage')
USE_FITS=$(tid 'https://projects.iq.harvard.edu/fits')
echo "  terms: image=$MODEL_IMAGE original=$USE_ORIGINAL service=$USE_SERVICE thumb=$USE_THUMB fits=$USE_FITS"

STAMP=$(date +%Y%m%d-%H%M%S)
docker exec houdini magick -size 1200x900 plasma:fractal jpg:- > "$TMP/smoketest-$STAMP.jpg"
echo "  generated $(wc -c < "$TMP/smoketest-$STAMP.jpg" | tr -d ' ') byte test image"

echo "== Ingest"
INGEST_EPOCH=$(date +%s)
start=$SECONDS
"${CURL[@]}" "${AUTH[@]}" -X POST "$BASE/node?_format=json" \
    -H 'Content-Type: application/json' \
    -d "{\"type\":[{\"target_id\":\"islandora_object\"}],
         \"title\":[{\"value\":\"smoketest-$STAMP\"}],
         \"field_model\":[{\"target_id\":$MODEL_IMAGE}]}" > "$TMP/node.json"
NID=$(json 'd["nid"][0]["value"]' < "$TMP/node.json") || { fail "create node: $(cat "$TMP/node.json")"; exit 1; }
UUID=$(json 'd["uuid"][0]["value"]' < "$TMP/node.json")
pass "created node $NID ($BASE/node/$NID)"

code=$("${CURL[@]}" "${AUTH[@]}" -o "$TMP/media.out" -w '%{http_code}' -X PUT \
    "$BASE/node/$NID/media/image/$USE_ORIGINAL" \
    -H 'Content-Type: image/jpeg' \
    -H "Content-Disposition: attachment; filename=\"smoketest-$STAMP.jpg\"" \
    -H "Content-Location: fedora://$(date +%Y-%m)/smoketest-$STAMP.jpg" \
    --data-binary "@$TMP/smoketest-$STAMP.jpg")
if [[ "$code" == 201 || "$code" == 204 ]]; then pass "uploaded original file (HTTP $code)"
else fail "upload original file (HTTP $code): $(head -c 300 "$TMP/media.out")"; exit 1; fi

# Media attached to the node with a given media use.
media_with_use() {
    sql "SELECT COUNT(*) FROM media__field_media_of o
         JOIN media__field_media_use u ON u.entity_id = o.entity_id
         WHERE o.field_media_of_target_id = $NID AND u.field_media_use_target_id = $1"
}
has_media() { [[ "$(media_with_use "$1")" -ge 1 ]]; }

ORIG_URI=$(sql "SELECT f.uri FROM media__field_media_of o
                JOIN media__field_media_use u ON u.entity_id = o.entity_id
                JOIN media__field_media_image i ON i.entity_id = o.entity_id
                JOIN file_managed f ON f.fid = i.field_media_image_target_id
                WHERE o.field_media_of_target_id = $NID AND u.field_media_use_target_id = $USE_ORIGINAL")
echo "  original file: $ORIG_URI"

echo "== Downstream (async, up to ${TIMEOUT}s each)"
start=$SECONDS

fcrepo_has() { [[ "$(docker exec fcrepo curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080/fcrepo/rest/$1")" == 200 ]]; }
NODE_PATH="${UUID:0:2}/${UUID:2:2}/${UUID:4:2}/${UUID:6:2}/$UUID"
wait_for "fcrepo: node resource /$NODE_PATH (milliner)" fcrepo_has "$NODE_PATH"
# fedora:// files are written straight to Fedora by Drupal's flysystem adapter.
ORIG_PATH=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1].removeprefix("fedora://")))' "$ORIG_URI")
wait_for "fcrepo: original binary /$ORIG_PATH (drupal flysystem)" fcrepo_has "$ORIG_PATH"

blazegraph_has() {
    docker exec blazegraph curl -s http://localhost:8080/bigdata/namespace/islandora/sparql \
        -H 'Accept: application/sparql-results+json' \
        --data-urlencode "query=ASK { <$BASE/node/$NID> ?p ?o }" | grep -q '"boolean" *: *true'
}
wait_for "blazegraph: triples for <$BASE/node/$NID> (alpaca)" blazegraph_has

wait_for "derivative: service file (alpaca -> houdini)" has_media "$USE_SERVICE"
wait_for "derivative: thumbnail (alpaca -> houdini)" has_media "$USE_THUMB"
wait_for "derivative: FITS technical metadata (alpaca -> crayfits -> fits)" has_media "$USE_FITS"

solr_has() {
    docker exec solr curl -s "http://localhost:8983/solr/default/select" \
        --data-urlencode "q=ss_search_api_id:\"entity:node/$NID:en\"" -d wt=json | grep -q '"numFound":1'
}
wait_for "solr: node indexed (drupal search_api)" solr_has

# The same info.json request the browser's image viewer makes, taken from the manifest.
cantaloupe_ok() {
    local id
    id=$("${CURL[@]}" "$BASE/node/$NID/manifest" | json 'd["sequences"][0]["canvases"][0]["images"][0]["resource"]["service"]["@id"]') || return 1
    "${CURL[@]}" "$id/info.json" | grep -q '"width"'
}
wait_for "cantaloupe: IIIF info.json via manifest (traefik -> cantaloupe -> drupal)" cantaloupe_ok

echo "== Logs since ingest"
errors=$(docker compose logs --since "$INGEST_EPOCH" --no-color 2>&1 \
    | grep -E 'ERROR|FATAL|Exception:|statusCode: [45]' | grep -vE '^\S+\s+\|\s+at ' || true)
if [[ -z "$errors" ]]; then pass "no errors logged"
else fail "errors logged:"; echo "$errors" | cut -c1-220 | head -20; fi

echo "== Cleanup"
if $KEEP || (( FAILED )); then
    echo "  kept node $NID for inspection. To remove it:"
    echo "    docker exec islandora drush entity:delete media \$(docker exec islandora drush sqlq \"SELECT GROUP_CONCAT(entity_id) FROM media__field_media_of WHERE field_media_of_target_id=$NID\")"
    echo "    docker exec islandora drush entity:delete node $NID"
else
    MIDS=$(sql "SELECT GROUP_CONCAT(entity_id) FROM media__field_media_of WHERE field_media_of_target_id = $NID")
    for mid in ${MIDS//,/ }; do "${CURL[@]}" "${AUTH[@]}" -X DELETE "$BASE/media/$mid?_format=json" -o /dev/null; done
    "${CURL[@]}" "${AUTH[@]}" -X DELETE "$BASE/node/$NID?_format=json" -o /dev/null
    pass "deleted node $NID and media $MIDS"
fi

echo
if (( FAILED )); then echo "SMOKE TEST FAILED"; exit 1; else echo "SMOKE TEST PASSED"; fi
