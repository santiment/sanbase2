defmodule SanbaseWeb.Graphql.Resolvers.EcosystemResolver do
  import Absinthe.Resolution.Helpers, except: [async: 1]
  alias SanbaseWeb.Graphql.SanbaseDataloader

  def get_ecosystems(_root, _args, _resolution) do
    Sanbase.Ecosystem.get_ecosystems_with_projects()
  end

  def aggregated_timeseries_data(%{name: ecosystem}, args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :ecosystem_aggregated_metric_data, {ecosystem, args})
    |> on_load(fn loader ->
      data = Dataloader.get(loader, SanbaseDataloader, :ecosystem_aggregated_metric_data, args)
      {:ok, data[ecosystem]}
    end)
  end

  def timeseries_data(%{id: id}, args, _resolution) do
    Sanbase.Ecosystem.get_timeseries_data(id, args)
  end
end
