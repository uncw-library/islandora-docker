FROM islandora/solr:7.0.18
# islandora/solr is Solr 10 plus the ocrhighlighting plugin and the
# analysis-extras/extraction/langid/ltr modules that this config relies on.

# The 'default' core (conf/ + core.properties) that Drupal's search_api_solr talks to.
# Its index lives in the solr-data volume, mounted at .../default/data by docker-compose.yml.
COPY ./default /opt/solr/server/solr/default
