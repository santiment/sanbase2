defmodule SanbaseWeb.Graphql.Resolvers.ProjectAnomaliesResolver do
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Anomaly

  def available_anomalies(%Project{slug: slug}, _args, _resolution) do
    Anomaly.available_anomalies(slug)
  end
end
