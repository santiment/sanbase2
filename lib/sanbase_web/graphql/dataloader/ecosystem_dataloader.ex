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

        {:ok, data} =
          Sanbase.Ecosystem.Metric.aggregated_timeseries_data(
            ecosystems,
            args.metric,
            args.from,
            args.to,
            opts
          )

        aggregated_transform_to_map(data, args)
      end,
      max_concurrency: 4,
      timeout: 60_000,
      ordered: false
    )
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
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

        {:ok, data} =
          Sanbase.Ecosystem.Metric.timeseries_data(
            ecosystems,
            args.metric,
            args.from,
            args.to,
            args.interval,
            opts
          )

        timeseries_transform_to_map(data, args)
      end,
      max_concurrency: 4,
      timeout: 60_000,
      ordered: false
    )
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
    |> IO.inspect()
  end

  defp timeseries_transform_to_map(data, args) do
    data
    |> Enum.reduce(%{}, fn %{ecosystem: ecosystem, datetime: dt, value: v}, acc ->
      elem = %{datetime: dt, value: v}
      Map.update(acc, {ecosystem, args}, [elem], &[elem | &1])
    end)
  end

  defp aggregated_transform_to_map(data, args) do
    data
    |> Enum.reduce(%{}, fn %{ecosystem: ecosystem, value: value}, acc ->
      Map.put(acc, {ecosystem, args}, value)
    end)
  end
end
