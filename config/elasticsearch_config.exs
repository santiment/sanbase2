use Mix.Config

config :sanbase, Sanbase.Elasticsearch.Cluster,
  url: "http://managed-elasticsearch-scraping-data.default.svc.cluster.local",
  api: Elasticsearch.API.HTTP,
  json_library: Jason

config :sanbase, Sanbase.Elasticsearch,
  indices: {:system, "ELASTICSEARCH_STATS_INDICES", "reddit"}
