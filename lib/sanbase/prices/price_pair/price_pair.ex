defmodule Sanbase.PricePair do
  import Sanbase.Price.PricePairSql

  import Sanbase.Utils.Transform,
    only: [
      maybe_unwrap_ok_value: 1,
      maybe_apply_function: 2
    ]

  import Sanbase.Metric.Transform, only: [exec_timeseries_data_query: 2]

  alias Sanbase.ClickhouseRepo

  @default_source "cryptocompare"

  @type error :: String.t()
  @type slug :: String.t()
  @type quote_asset :: String.t()
  @type slugs :: list(slug)
  @type interval :: String.t()
  @type opts :: Keyword.t()

  @type timeseries_data_map :: %{
          datetime: DateTime.t(),
          slug: slug,
          value: float()
        }

  @type timeseries_data_result :: {:ok, list(timeseries_data_map())} | {:error, error()}

  @type timeseries_metric_data_map :: %{
          datetime: DateTime.t(),
          value: float() | nil
        }

  @type timeseries_metric_data_result ::
          {:ok, list(timeseries_metric_data_map())} | {:error, error()}

  @type aggregated_metric_timeseries_data_map :: %{String.t() => float()}

  @type aggregated_metric_timeseries_data_result ::
          {:ok, aggregated_metric_timeseries_data_map()} | {:error, error()}

  @type last_record_before_map :: %{
          datetime: DateTime.t(),
          value: float()
        }

  @type last_record_before_result :: {:ok, last_record_before_map()} | {:error, error()}

  @doc ~s"""
  Return timeseries data for the given time period where every point consists
  of datetime and price in `quote_asset`
  """

  def timeseries_data(slug_or_slugs, quote_asset, from, to, interval, opts \\ [])

  def timeseries_data([], _quote_asset, _from, _to, _interval, _opts), do: {:ok, []}

  def timeseries_data(slug_or_slugs, quote_asset, from, to, interval, opts) do
    source = Keyword.get(opts, :source) || @default_source
    aggregation = Keyword.get(opts, :aggregation) || :last

    {query, args} =
      timeseries_data_query(
        slug_or_slugs,
        quote_asset,
        from,
        to,
        interval,
        source,
        aggregation
      )

    # Handle both cases where the aggregation is OHLC or it's not
    exec_timeseries_data_query(query, args)
  end

  def timeseries_data_per_slug([], _quote_asset, _from, _to, _interval, _opts), do: {:ok, []}

  def timeseries_data_per_slug(slug_or_slugs, quote_asset, from, to, interval, opts) do
    source = Keyword.get(opts, :source) || @default_source
    aggregation = Keyword.get(opts, :aggregation) || :last
    slugs = List.wrap(slug_or_slugs)

    {query, args} =
      timeseries_data_per_slug_query(slugs, quote_asset, from, to, interval, source, aggregation)

    ClickhouseRepo.query_reduce(query, args, %{}, fn [timestamp, slug, value], acc ->
      datetime = DateTime.from_unix!(timestamp)
      elem = %{slug: slug, value: value}
      Map.update(acc, datetime, [elem], &[elem | &1])
    end)
    |> maybe_apply_function(fn list ->
      Enum.map(list, fn {datetime, data} -> %{datetime: datetime, data: data} end)
    end)
    |> maybe_apply_function(fn list ->
      Enum.sort_by(list, & &1.datetime, {:asc, DateTime})
    end)
  end

  @doc ~s"""
  Returns aggregated price in `quote_asset` for the given slugs and time period.
  """

  def aggregated_timeseries_data(slug_or_slugs, quote_asset, from, to, opts \\ [])

  def aggregated_timeseries_data([], _, _, _, _), do: {:ok, []}

  def aggregated_timeseries_data(slugs, quote_asset, from, to, opts)
      when is_list(slugs) and length(slugs) > 50 do
    result =
      Enum.chunk_every(slugs, 50)
      |> Sanbase.Parallel.map(
        &aggregated_timeseries_data(&1, quote_asset, from, to, opts),
        timeout: 25_000,
        max_concurrency: 8,
        ordered: false
      )
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(&elem(&1, 1))
      |> Enum.reduce(%{}, &Map.merge(&1, &2))

    {:ok, result}
  end

  def aggregated_timeseries_data(slug_or_slugs, quote_asset, from, to, opts) do
    source = Keyword.get(opts, :source, @default_source)
    aggregation = Keyword.get(opts, :aggregation) || :last
    slugs = List.wrap(slug_or_slugs)

    {query, args} =
      aggregated_timeseries_data_query(slugs, quote_asset, from, to, source, aggregation)

    ClickhouseRepo.query_reduce(query, args, %{}, fn [slug, value, has_changed], acc ->
      # This way if the slug does not have any data still include it in the result
      # with value `nil`. This way the API can cache the result. In case one of the
      # aggregated_timeseries_data calls fails, the slugs in it won't be included
      # at all and they will be retried next time.
      value = if has_changed == 1, do: value, else: nil
      Map.put(acc, slug, value)
    end)
  end

  def slugs_by_filter(quote_asset, from, to, operator, threshold, opts \\ [])

  def slugs_by_filter(quote_asset, from, to, operator, threshold, opts) do
    aggregation = Keyword.get(opts, :aggregation) || :last
    source = Keyword.get(opts, :source, @default_source)

    {query, args} =
      slugs_by_filter_query(quote_asset, from, to, source, operator, threshold, aggregation)

    ClickhouseRepo.query_transform(query, args, fn [slug, _value] -> slug end)
  end

  def slugs_order(quote_asset, from, to, direction, opts \\ [])

  def slugs_order(quote_asset, from, to, direction, opts) do
    aggregation = Keyword.get(opts, :aggregation) || :last
    source = Keyword.get(opts, :source, @default_source)
    {query, args} = slugs_order_query(quote_asset, from, to, source, direction, aggregation)
    ClickhouseRepo.query_transform(query, args, fn [slug, _value] -> slug end)
  end

  @doc ~s"""
  Return the last record  before the given `datetime`
  """
  def last_record_before(slug, quote_asset, datetime, opts \\ [])

  def last_record_before(slug, quote_asset, datetime, opts) do
    source = Keyword.get(opts, :source, @default_source)
    {query, args} = last_record_before_query(slug, quote_asset, datetime, source)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [unix, value] ->
        %{
          datetime: DateTime.from_unix!(unix),
          value: value
        }
      end
    )
    |> maybe_unwrap_ok_value()
  end

  def available_slugs(opts \\ [])

  def available_slugs(opts) do
    case Keyword.get(opts, :source) || @default_source do
      "cryptocompare" ->
        slugs =
          Sanbase.Model.Project.SourceSlugMapping.get_source_slug_mappings("cryptocompare")
          |> Enum.map(&elem(&1, 1))

        {:ok, slugs}

      _ ->
        {:error, "Only cryptocompare is supported as source."}
    end
  end

  def available_slugs(quote_asset, opts) do
    source = Keyword.get(opts, :source) || @default_source
    {query, args} = available_slugs_query(quote_asset, source)

    ClickhouseRepo.query_transform(query, args, fn [slug] -> slug end)
  end

  def has_data?(slug, quote_asset, opts \\ [])

  def has_data?(slug, quote_asset, opts) do
    source = Keyword.get(opts, :source, @default_source)
    {query, args} = select_any_record_query(slug, quote_asset, source)

    ClickhouseRepo.query_transform(query, args, & &1)
    |> case do
      {:ok, [_]} -> {:ok, true}
      {:ok, []} -> {:ok, false}
      {:error, error} -> {:error, error}
    end
  end

  def available_quote_assets(slug, opts \\ [])

  def available_quote_assets(slug, opts) do
    source = Keyword.get(opts, :source, @default_source)
    {query, args} = available_quote_assets_query(slug, source)

    ClickhouseRepo.query_transform(query, args, fn [quote_asset] -> quote_asset end)
  end

  @doc ~s"""
  Return the first datetime for which `slug` has data
  """
  @spec first_datetime(slug, quote_asset, opts) ::
          {:ok, DateTime.t()} | {:ok, nil} | {:error, error}
  def first_datetime(slug, quote_asset, opts \\ [])

  def first_datetime(slug, quote_asset, opts) do
    source = Keyword.get(opts, :source, @default_source)
    {query, args} = first_datetime_query(slug, quote_asset, source)

    ClickhouseRepo.query_transform(query, args, fn
      [timestamp] -> DateTime.from_unix!(timestamp)
    end)
    |> maybe_unwrap_ok_value()
  end

  def last_datetime_computed_at(_slug, _quote_asset, _opts) do
    # TODO FIXME
    {:ok, DateTime.utc_now()}
  end
end
