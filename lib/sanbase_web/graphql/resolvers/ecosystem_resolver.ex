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
      case Dataloader.get(
             loader,
             SanbaseDataloader,
             :ecosystem_aggregated_metric_data,
             {ecosystem, args}
           ) do
        nil -> fetch_error("aggregatedTimeseriesData", args.metric, ecosystem)
        value -> {:ok, value}
      end
    end)
  end

  def timeseries_data(
        root,
        %{from: from, to: to, interval: interval} = args,
        resolution
      ) do
    with {:ok, transform} <- MetricTransform.args_to_transform(args),
         {:ok, from} <- MetricTransform.calibrate_transform_params(transform, from, to, interval) do
      args = Map.merge(args, %{original_from: args[:from], from: from, transform: transform})
      get_timeseries_data(root, args, resolution)
    end
  end

  defp get_timeseries_data(%{name: ecosystem}, args, %{context: %{loader: loader}}) do
    key = :ecosystem_timeseries_metric_data

    loader
    |> Dataloader.load(SanbaseDataloader, key, {ecosystem, args})
    |> on_load(fn loader ->
      with result when is_list(result) <-
             Dataloader.get(loader, SanbaseDataloader, key, {ecosystem, args}),
           {:ok, result} <- MetricTransform.apply_transform(args.transform, result),
           {:ok, result} <- fit_from_datetime(result, %{args | from: args.original_from}) do
        {:ok, result}
      else
        nil -> fetch_error("timeseriesData", args.metric, ecosystem)
        error -> error
      end
    end)
  end

  # The dataloader fills every key it fetched, so nil means a failed or timed out fetch
  defp fetch_error(field, metric, ecosystem) do
    {:error, "Failed to fetch #{field} for metric #{metric} and ecosystem #{ecosystem}"}
  end
end
