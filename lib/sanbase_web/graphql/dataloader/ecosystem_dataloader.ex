defmodule SanbaseWeb.Graphql.EcosystemDataloader do
  def data(), do: Dataloader.KV.new(&query/2)

  def query(:ecosystem_aggregated_metric_data, data) do
    # The key is the arguments, the value is the list of ecosystems
    # The args are from/to/interval/aggregation/metric
    map =
      Enum.group_by(
        data,
        fn {_ecosystem, args} -> args end,
        fn {ecosystem, _args} -> ecosystem end
      )

    Sanbase.Parallel.map(
      map,
      fn {args, ecosystems} ->
        opts = [aggregation: args[:aggregation]]

        Sanbase.Ecosystem.Metric.aggregated_timeseries_data(
          ecosystems,
          args.metric,
          args.from,
          args.to,
          opts
        )
      end,
      max_concurrency: 4,
      timeout: 60_000,
      ordered: false
    )
    |> transform_to_map()
  end

  def query(:ecosystem_timeseries_metric_data, data) do
    # The key is the arguments, the value is the list of ecosystems
    # The args are from/to/interval/aggregation/metric
    map =
      Enum.group_by(
        data,
        fn {_ecosystem, args} -> args end,
        fn {ecosystem, _args} -> ecosystem end
      )

    Sanbase.Parallel.map(
      map,
      fn {args, ecosystems} ->
        opts = [aggregation: args[:aggregation]]

        Sanbase.Ecosystem.Metric.aggregated_timeseries_data(
          ecosystems,
          args.metric,
          args.from,
          args.to,
          opts
        )
      end,
      max_concurrency: 4,
      timeout: 60_000,
      ordered: false
    )
    |> transform_to_map()
  end

  defp transform_to_map(result) do
    result
  end
end
