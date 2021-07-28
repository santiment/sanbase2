defmodule Sanbase.Signal.SignalAdapter do
  @behaviour Sanbase.Signal.Behaviour

  import Sanbase.Signal.SqlQuery
  import Sanbase.Utils.Transform, only: [maybe_unwrap_ok_value: 1, maybe_apply_function: 2]

  alias Sanbase.Signal.FileHandler
  alias Sanbase.ClickhouseRepo

  @aggregations FileHandler.aggregations()
  @aggregation_map FileHandler.aggregation_map()
  @signals_mapset FileHandler.signals_mapset()
  @min_interval_map FileHandler.min_interval_map()
  @signals @signals_mapset |> Enum.to_list()
  @data_type_map FileHandler.data_type_map()
  @selectors_map FileHandler.selectors_map()
  @human_readable_name_map FileHandler.human_readable_name_map()
  @signal_to_name_map FileHandler.signal_to_name_map()
  @access_map FileHandler.access_map()
  @min_plan_map FileHandler.min_plan_map()
  @free_signals FileHandler.signals_with_access(:free)
  @restricted_signals FileHandler.signals_with_access(:restricted)
  @timeseries_signals FileHandler.signals_with_data_type(:timeseries)

  def has_signal?(signal) do
    case signal in @signals_mapset do
      true -> true
      false -> signal_not_available_error(signal)
    end
  end

  def available_aggregations(), do: @aggregations

  def human_readable_name(signal) do
    case Map.get(@human_readable_name_map, signal) do
      nil ->
        signal_not_available_error(signal)

      human_readable_name ->
        human_readable_name
    end
  end

  def free_signals(), do: @free_signals

  def restricted_signals(), do: @restricted_signals

  def available_timeseries_signals(), do: @timeseries_signals

  def access_map() do
    @access_map
    |> Enum.into(%{}, fn {signal, restrictions} ->
      {signal, resolve_restrictions(restrictions)}
    end)
  end

  def min_plan_map(), do: @min_plan_map

  @impl Sanbase.Signal.Behaviour
  def available_signals(), do: @signals

  @impl Sanbase.Signal.Behaviour
  def available_signals(%{slug: slug}) when is_binary(slug) do
    {query, args} = available_signals_query(slug)

    ClickhouseRepo.query_transform(query, args, fn [signal] ->
      Map.get(@signal_to_name_map, signal)
    end)
    |> maybe_apply_function(fn list -> Enum.reject(list, &is_nil/1) end)
  end

  @impl Sanbase.Signal.Behaviour
  def available_slugs(signal) do
    {query, args} = available_slugs_query(signal)

    ClickhouseRepo.query_transform(query, args, fn [slug] -> slug end)
  end

  @impl Sanbase.Signal.Behaviour
  def metadata(signal) do
    {:ok,
     %{
       signal: signal,
       min_interval: Map.get(@min_interval_map, signal),
       default_aggregation: Map.get(@aggregation_map, signal),
       available_aggregations: @aggregations,
       available_selectors: Map.get(@selectors_map, signal),
       data_type: Map.get(@data_type_map, signal),
       complexity_weight: 0.3
     }}
  end

  @impl Sanbase.Signal.Behaviour
  def first_datetime(signal, %{slug: slug}) when is_binary(slug) do
    {query, args} = first_datetime_query(signal, slug)

    ClickhouseRepo.query_transform(query, args, fn [datetime] ->
      DateTime.from_unix!(datetime)
    end)
    |> maybe_unwrap_ok_value()
  end

  @impl Sanbase.Signal.Behaviour
  def raw_data(signals, selector, from, to) do
    {query, args} = raw_data_query(signals, from, to)

    ClickhouseRepo.query_transform(query, args, fn [unix, signal, slug, value, metadata] ->
      metadata =
        case Jason.decode(metadata) do
          {:ok, value} -> value
          _ -> %{}
        end

      %{
        datetime: DateTime.from_unix!(unix),
        signal: Map.get(@signal_to_name_map, signal),
        slug: slug,
        value: value,
        metadata: metadata
      }
    end)
    |> maybe_apply_function(fn list -> Enum.filter(list, & &1.signal) end)
    |> maybe_apply_function(fn list -> filter_slugs_by_selector(list, selector) end)
  end

  @impl Sanbase.Signal.Behaviour
  def timeseries_data(_signal, %{slug: []}, _from, _to, _interval, _opts), do: {:ok, []}

  def timeseries_data(signal, %{slug: slug_or_slugs}, from, to, interval, opts)
      when is_binary(slug_or_slugs) or is_list(slug_or_slugs) do
    aggregation = Keyword.get(opts, :aggregation, nil) || Map.get(@aggregation_map, signal)
    slugs = slug_or_slugs |> List.wrap()

    {query, args} = timeseries_data_query(signal, slugs, from, to, interval, aggregation)

    ClickhouseRepo.query_transform(query, args, fn [unix, value, metadata] ->
      metadata =
        metadata
        |> List.wrap()
        |> Enum.map(&Jason.decode/1)
        |> Enum.reduce_while([], fn
          {:ok, value}, acc -> {:cont, [value | acc]}
          _, _ -> {:halt, []}
        end)
        |> Enum.reverse()

      %{
        datetime: DateTime.from_unix!(unix),
        value: value,
        metadata: metadata
      }
    end)
  end

  @impl Sanbase.Signal.Behaviour
  def aggregated_timeseries_data(signal, selector, from, to, opts)
  def aggregated_timeseries_data(_signal, nil, _from, _to, _opts), do: {:ok, []}
  def aggregated_timeseries_data(_signal, [], _from, _to, _opts), do: {:ok, []}

  def aggregated_timeseries_data(signal, %{slug: slug_or_slugs}, from, to, opts)
      when is_binary(slug_or_slugs) or is_list(slug_or_slugs) do
    aggregation = Keyword.get(opts, :aggregation, nil) || Map.get(@aggregation_map, signal)
    slugs = slug_or_slugs |> List.wrap()

    {query, args} = aggregated_timeseries_data_query(signal, slugs, from, to, aggregation)

    ClickhouseRepo.query_reduce(query, args, %{}, fn [slug, value], acc ->
      Map.put(acc, slug, value)
    end)
  end

  # Private functions
  defp signal_not_available_error(signal) do
    %{close: close, error_msg: error_msg} = signal_not_available_error_details(signal)

    case close do
      nil -> {:error, error_msg}
      close -> {:error, error_msg <> " Did you mean '#{close}'?"}
    end
  end

  defp signal_not_available_error_details(signal) do
    %{
      close: Enum.find(@signals_mapset, &(String.jaro_distance(signal, &1) > 0.8)),
      error_msg: "The signal '#{signal}' is not supported or is mistyped."
    }
  end

  defp filter_slugs_by_selector(list, :all), do: list

  defp filter_slugs_by_selector(list, %{slug: slug_or_slugs}) do
    slugs = List.wrap(slug_or_slugs)
    Enum.filter(list, &(&1.slug in slugs))
  end

  # In case more signal adapters are added, functions such as this
  # should be packed in a Helper module to be used on all the signal data.
  # The same way the metric modules are structured
  defp resolve_restrictions(restrictions) when is_map(restrictions) do
    Enum.into(restrictions, %{}, fn {k, v} -> {k, String.to_existing_atom(v)} end)
  end

  defp resolve_restrictions(restriction) when restriction in [:restricted, :free] do
    %{"historical" => restriction, "realtime" => restriction}
  end
end
