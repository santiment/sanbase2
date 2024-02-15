defmodule SanbaseWeb.Graphql.Resolvers.EcosystemResolver do
  import Absinthe.Resolution.Helpers, except: [async: 1]
  alias SanbaseWeb.Graphql.SanbaseDataloader

  def get_ecosystems(_root, args, _resolution) do
    ecosystems = args[:ecosystems] || :all
    Sanbase.Ecosystem.get_ecosystems_with_projects(ecosystems)
  end

  def aggregated_timeseries_data(%{name: ecosystem}, args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :ecosystem_aggregated_metric_data, {ecosystem, args})
    |> on_load(fn loader ->
      data =
        Dataloader.get(
          loader,
          SanbaseDataloader,
          :ecosystem_aggregated_metric_data,
          {ecosystem, args}
        )

      {:ok, data}
    end)
  end

  def timeseries_data(%{name: ecosystem}, args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :ecosystem_timeseries_metric_data, {ecosystem, args})
    |> on_load(fn loader ->
      data =
        Dataloader.get(
          loader,
          SanbaseDataloader,
          :ecosystem_timeseries_metric_data,
          {ecosystem, args}
        )

      {:ok, data}
    end)
  end
end
