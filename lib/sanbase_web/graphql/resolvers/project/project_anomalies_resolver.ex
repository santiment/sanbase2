defmodule SanbaseWeb.Graphql.Resolvers.ProjectAnomaliesResolver do
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Anomaly

  def available_anomalies(%Project{slug: slug}, _args, _resolution) do
    Anomaly.available_anomalies(slug)
  end

  def available_anomalies_per_metric(%Project{slug: slug}, _args, _resolution) do
    Anomaly.available_anomalies(slug, anomalies_per_metric: true)
  end
end
