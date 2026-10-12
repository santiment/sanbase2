defmodule SanbaseWeb.Graphql.EcosystemDataloader do
  def query(:ecosystem_aggregated_metric_data, data, ctx) do
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

        case Sanbase.Ecosystem.Metric.aggregated_timeseries_data(
               ecosystems,
               args.metric,
               args.from,
               args.to,
               opts
             ) do
          {:ok, data} -> aggregated_transform_to_map(data, args)
          {:error, error} -> errors_map(ecosystems, args, error)
        end
      end,
      max_concurrency: 4,
      timeout: Sanbase.Parallel.dataloader_timeout(),
      on_timeout: :drop,
      label: "EcosystemDataloader :ecosystem_aggregated_metric_data",
      ordered: false,
      request_context: ctx
    )
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  def query(:ecosystem_timeseries_metric_data, data, ctx) do
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

        case Sanbase.Ecosystem.Metric.timeseries_data(
               ecosystems,
               args.metric,
               args.from,
               args.to,
               args.interval,
               opts
             ) do
          {:ok, data} -> timeseries_transform_to_map(data, args)
          {:error, error} -> errors_map(ecosystems, args, error)
        end
      end,
      max_concurrency: 4,
      timeout: Sanbase.Parallel.dataloader_timeout(),
      on_timeout: :drop,
      label: "EcosystemDataloader :ecosystem_timeseries_metric_data",
      ordered: false,
      request_context: ctx
    )
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  # Dataloader.KV stores the error per key instead of failing the whole batch
  defp errors_map(ecosystems, args, error) do
    Map.new(ecosystems, fn ecosystem -> {{ecosystem, args}, {:error, error}} end)
  end

  defp timeseries_transform_to_map(data, args) do
    data
    |> Enum.reduce(%{}, fn %{ecosystem: ecosystem, datetime: dt, value: v}, acc ->
      elem = %{datetime: dt, value: v}
      Map.update(acc, {ecosystem, args}, [elem], &[elem | &1])
    end)
    |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
  end

  defp aggregated_transform_to_map(data, args) do
    data
    |> Enum.reduce(%{}, fn %{ecosystem: ecosystem, value: value}, acc ->
      Map.put(acc, {ecosystem, args}, value)
    end)
  end
end
