defmodule SanbaseWeb.Graphql.Resolvers.EcosystemResolver do
  import Absinthe.Resolution.Helpers, except: [async: 1]
  import SanbaseWeb.Graphql.Helpers.Utils, only: [fit_from_datetime: 2]

  alias SanbaseWeb.Graphql.Resolvers.MetricTransform
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
        ) || 0

      {:ok, data}
    end)
  end

  def timeseries_data(
        root,
        %{from: from, to: to, interval: interval} = args,
        resolution
      ) do
    with {:ok, transform} <- MetricTransform.args_to_transform(args),
         {:ok, from} <- MetricTransform.calibrate_transform_params(transform, from, to, interval),
         args = Map.merge(args, %{original_from: args[:from], from: from, transform: transform}),
         {:ok, result} <- get_timeseries_data(root, args, resolution) do
      {:ok, result}
    end
  end

  defp get_timeseries_data(%{name: ecosystem}, args, %{context: %{loader: loader}}) do
    key = :ecosystem_timeseries_metric_data

    loader
    |> Dataloader.load(SanbaseDataloader, key, {ecosystem, args})
    |> on_load(fn loader ->
      result = Dataloader.get(loader, SanbaseDataloader, key, {ecosystem, args}) || []

      with {:ok, result} <- MetricTransform.apply_transform(args.transform, result),
           {:ok, result} <- fit_from_datetime(result, %{args | from: args.original_from}) do
        {:ok, result}
      end
    end)
  end
end
