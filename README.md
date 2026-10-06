# Islanodora Docker

Downstream output of https://github.com/Islandora-Devops/isle-site-template.  Heavily modified & trimmed.

## Update steps
   - check upstream for the latest image versions.  Bump the docker-compose to those versions.
   - check for upstream changes to env_files variables.
   - check for upstream code/config changes.

Why not just use isle-site-template as is?
   - that repo installed a root cert on my work macbook
   - more explicit env setup, fewer shared variables
   - simpler docker-compose.yml

## Dev box
   - copy ./sample_env_files to ./env_files
   - set the values:
      - make equal values for MATCH_x items across the files
      - change CHANGEME items to a secret value
      - others can stay as they are
   - make the ./env_files jwt files
      - run in bash shell:  `source make_jwt_files.sh`
   - make the ./dev_certs files
      - run in bash shell: `sudo ./make_cert_files.sh`

## Refresh the solr index
   - `docker compose exec drupal drush search-api:reset-tracker`
   - `docker compose exec drupal drush search-api:index`

## Refresh the Blazegraph index
   - `docker compose exec drupal drush php:eval '\Drupal::service("account_switcher")->switchTo(\Drupal\user\Entity\User::load(1)); foreach (["node" => "index_node_in_triplestore", "media" => "index_media_in_triplestore", "taxonomy_term" => "index_taxonomy_term_in_the_triplestore"] as $t => $a) { $ids = \Drupal::entityQuery($t)->accessCheck(FALSE)->execute(); \Drupal::entityTypeManager()->getStorage("action")->load($a)->execute(\Drupal::entityTypeManager()->getStorage($t)->loadMultiple($ids)); echo count($ids) . " $t queued\n"; }'`

## Look at your dev container's web UIs
   - Traefik: https://traefik.islandora.dev/dashboard/#/
   - Drupal: https://islandora.dev/admin/content
   - Fedora: https://fcrepo.islandora.dev/fcrepo/rest
   - Blazegraph: https://blazegraph.islandora.dev/bigdata/#query
      - First select the 'islandora' namespace (Namespaces tab -> "Use" next to islandora).
      - The page defaults to the empty 'kb' namespace, so queries there return 0 results.
      - An example query:
           
               PREFIX pcdm: <http://pcdm.org/models#>
               PREFIX dcterms: <http://purl.org/dc/terms/>

               SELECT ?item ?title ?type
               WHERE {
               ?item a ?type .
               FILTER(?type IN (pcdm:Collection, pcdm:Object))
               OPTIONAL { ?item dcterms:title ?title }
               }
               ORDER BY ?type ?title
   - ActiveMQ: https://activemq.islandora.dev/admin/topics.jsp
   - Cantaloupe: https://islandora.dev/cantaloupe/health
   - Solr: https://solr.islandora.dev/solr/#/default/query



## Hard refresh
   - `docker compose down -v`
   - `rm -r ./mounted`
   - (?? make new certs_files & new jwt_files ??)
   - `docker compose up -d && docker compose logs -f`

## To build images
   `docker build --no-cache --platform=linux/amd64 --build-arg REPOSITORY=islandora --build-arg TAG=7.0.18 -t uncwlibrary/islandora-drupal:7.0.18 ./drupal`
   `docker build --no-cache --platform=linux/amd64 -t uncwlibrary/islandora-solr:7.0.18 ./solr`

## Production
   - use the branch matching your servername
   - set the env_files
   - run `./make_jwt_files.sh`


