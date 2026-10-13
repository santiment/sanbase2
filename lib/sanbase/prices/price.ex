defmodule Sanbase.Price do
  use Ecto.Schema

  import Sanbase.Price.SqlQuery

  import Sanbase.Utils.Transform,
    only: [
      maybe_unwrap_ok_value: 1,
      maybe_apply_function: 2,
      maybe_transform_datetime_data_tuple_to_map: 1,
      wrap_ok: 1
    ]

  import Sanbase.Metric.Transform,
    only: [
      maybe_nullify_values: 1,
      remove_missing_values: 1,
      exec_timeseries_data_query: 1
    ]

  alias Sanbase.Project
  alias Sanbase.ClickhouseRepo

  @default_source "coinmarketcap"
  @supported_sources ["coinmarketcap", "cryptocompare"]
  @supported_sources_str Enum.join(@supported_sources, ", ")
  @deprecated_sources ["kaiko"]

  @metrics [:price_usd, :price_btc, :marketcap_usd, :volume_usd]
  @metrics @metrics ++ Enum.map(@metrics, &Atom.to_string/1)
  @aggregations Sanbase.Metric.SqlQuery.Helper.aggregations()

  @type metric :: String.t() | Atom.t()
  @type error :: String.t()
  @type slug :: String.t()
  @type slugs :: list(slug)
  @type interval :: String.t()
  @type opts :: Keyword.t()

  @type timeseries_data_map :: %{
          datetime: DateTime.t(),
          slug: slug,
          price_usd: float() | nil,
          price_btc: float() | nil,
          marketcap: float(),
          marketcap_usd: float() | nil,
          volume: float() | nil,
          volume_usd: float() | nil
        }

  @type timeseries_data_result :: {:ok, list(timeseries_data_map())} | {:error, error()}

  @type timeseries_metric_data_map :: %{
          datetime: DateTime.t(),
          value: float() | nil
        }

  @type timeseries_metric_data_result ::
          {:ok, list(timeseries_metric_data_map())} | {:error, error()}

  @type aggregated_metric_timeseries_data_map :: %{
          String.t() => float()
        }

  @type aggregated_metric_timeseries_data_result ::
          {:ok, aggregated_metric_timeseries_data_map()} | {:error, error()}

  @type aggregated_marketcap_and_volume_map :: %{
          slug: slug,
          marketcap: float() | nil,
          marketcap_usd: float() | nil,
          volume: float() | nil,
          volume_usd: float() | nil
        }

  @type aggregated_marketcap_and_volume_result ::
          {:ok, list(aggregated_marketcap_and_volume_map())} | {:error, error()}

  @type ohlc_map :: %{
          open_price_usd: float() | nil,
          high_price_usd: float() | nil,
          close_price_usd: float() | nil,
          low_price_usd: float() | nil
        }

  @type ohlc_result :: {:ok, ohlc_map()} | {:error, error()}

  @type timeseries_ohlc_data_map :: %{
          datetime: DateTime.t(),
          open_price_usd: float() | nil,
          high_price_usd: float() | nil,
          close_price_usd: float() | nil,
          low_price_usd: float() | nil
        }

  @type timeseries_ohlc_data_result :: {:ok, list(timeseries_ohlc_data_map())} | {:error, error()}

  @type last_record_before_map :: %{
          price_usd: float() | nil,
          price_btc: float() | nil,
          marketcap: float(),
          marketcap_usd: float() | nil,
          volume: float() | nil,
          volume_usd: float() | nil
        }

  @type last_record_before_result :: {:ok, last_record_before_map()} | {:error, error()}

  @type combined_marketcap_and_volume_map :: %{
          datetime: DateTime.t(),
          marketcap_usd: float(),
          marketcap: float(),
          volume_usd: float(),
          volume: float()
        }

  @type combined_marketcap_and_volume_result ::
          {:ok, list(combined_marketcap_and_volume_map())} | {:error, error()}

  @table "asset_prices_v3"
  schema @table do
    field(:datetime, :naive_datetime, source: :dt)
    field(:source, :string)
    field(:slug, :string)
    field(:price_usd, :float)
    field(:price_btc, :float)
    field(:marketcap_usd, :float)
    field(:volume_usd, :float)
  end

  def table(), do: @table
  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _), do: raise("Cannot change the asset_prices table")

  @doc ~s"""
  Return timeseries data for the given time period where every point consists
  of price in USD, price in BTC, marketcap in USD and volume in USD
  """
  @spec timeseries_data(slug | list(slug), DateTime.t(), DateTime.t(), interval, opts) ::
          timeseries_data_result
  def timeseries_data(slug, from, to, interval, opts \\ [])

  def timeseries_data("TOTAL_ERC20", from, to, interval, opts) do
    # Break here otherwise the Enum.filter/2 will remove all errors and report a wrong result
    with {:ok, _source} <- opts_to_source(opts) do
      Project.List.erc20_projects_slugs()
      |> combined_marketcap_and_volume(from, to, interval, opts)
    end
  end

  def timeseries_data(slug_or_slugs, from, to, interval, opts) do
    with {:ok, source} <- opts_to_source(opts) do
      aggregation = Keyword.get(opts, :aggregation) || :last

      query_struct = timeseries_data_query(slug_or_slugs, from, to, interval, source, aggregation)

      ClickhouseRepo.query_transform(
        query_struct,
        fn [timestamp, price_usd, price_btc, marketcap_usd, volume_usd] ->
          %{
            datetime: DateTime.from_unix!(timestamp),
            price_usd: price_usd,
            price_btc: price_btc,
            marketcap_usd: marketcap_usd,
            marketcap: marketcap_usd,
            volume_usd: volume_usd,
            volume: volume_usd
          }
        end
      )
    end
  end

  @doc ~s"""
  Return timeseries data for the given time period where every point consists
  of price in USD, price in BTC, marketcap in USD and volume in USD
  """
  @spec timeseries_metric_data(
          slug | list(slug),
          metric,
          DateTime.t(),
          DateTime.t(),
          interval,
          opts
        ) ::
          timeseries_metric_data_result
  def timeseries_metric_data(slug_or_slugs, metric, from, to, interval, opts \\ [])

  def timeseries_metric_data([], _, _, _, _, _), do: {:ok, []}

  # TODO: Use the source
  def timeseries_metric_data("TOTAL_ERC20", metric, from, to, interval, opts) do
    with {:ok, _source} <- opts_to_source(opts) do
      Project.List.erc20_projects_slugs()
      |> combined_marketcap_and_volume(from, to, interval, opts)
      |> maybe_apply_function(fn result ->
        metric = String.to_existing_atom(metric)

        result
        |> Enum.map(fn %{^metric => value, datetime: datetime} ->
          %{datetime: datetime, value: value}
        end)
      end)
    end
  end

  def timeseries_metric_data(slug_or_slugs, metric, from, to, interval, opts) do
    with {:ok, source} <- opts_to_source(opts) do
      aggregation = Keyword.get(opts, :aggregation) || :last

      timeseries_metric_data_query(
        slug_or_slugs,
        metric,
        from,
        to,
        interval,
        source,
        aggregation
      )
      |> exec_timeseries_data_query()
    end
  end

  def timeseries_metric_data_per_slug([], _, _, _, _, _), do: {:ok, []}

  def timeseries_metric_data_per_slug(slug_or_slugs, metric, from, to, interval, opts) do
    with {:ok, source} <- opts_to_source(opts) do
      aggregation = Keyword.get(opts, :aggregation) || :last

      query_struct =
        timeseries_metric_data_per_slug_query(
          slug_or_slugs,
          metric,
          from,
          to,
          interval,
          source,
          aggregation
        )

      ClickhouseRepo.query_reduce(query_struct, %{}, fn [timestamp, slug, value], acc ->
        datetime = DateTime.from_unix!(timestamp)
        elem = %{slug: slug, value: value}
        Map.update(acc, datetime, [elem], &[elem | &1])
      end)
      |> maybe_transform_datetime_data_tuple_to_map()
    end
  end

  @doc ~s"""
  Returns aggregated price in USD, price in BTC, marketcap in USD and
  volume in USD for the given slugs and time period.

  The aggregation can be changed by providing the following keyword parameters:
  - :price_aggregation (:avg by default) - control price in USD and BTC aggregation
  - :volume_aggregation (:avg by default) - control the volume aggregation
  - :marketcap_aggregation (:avg by default) - control the marketcap aggregation

  The available aggregations are #{inspect(@aggregations)}
  """
  @spec aggregated_timeseries_data(slug | slugs, DateTime.t(), DateTime.t(), opts) ::
          {:ok, list(map())} | {:error, String.t()}
  def aggregated_timeseries_data(slug_or_slugs, from, to, opts \\ [])

  def aggregated_timeseries_data([], _, _, _), do: {:ok, []}

  def aggregated_timeseries_data(slug_or_slugs, from, to, opts)
      when is_binary(slug_or_slugs) or is_list(slug_or_slugs) do
    with {:ok, source} <- opts_to_source(opts) do
      slugs = List.wrap(slug_or_slugs)

      query_struct = aggregated_timeseries_data_query(slugs, from, to, source)

      ClickhouseRepo.query_transform(query_struct, fn
        [slug, price_usd, price_btc, marketcap_usd, volume_usd, has_changed] ->
          %{
            slug: slug,
            price_usd: price_usd,
            price_btc: price_btc,
            marketcap_usd: marketcap_usd,
            marketcap: marketcap_usd,
            volume_usd: volume_usd,
            volume: volume_usd,
            has_changed: has_changed
          }
      end)
      |> maybe_nullify_values()
    end
  end

  @doc ~s"""
  Return the aggregated data for all slugs for the provided metric in
  the given interval
  The default aggregation can be overriden by passing the :aggregation
  key with as part of the keyword options list.
  The supported aggregations are: #{inspect(@aggregations)}

  In the success case the result is a map where the slug is the key and the value
  is the aggregated metric's value
  """
  @spec aggregated_metric_timeseries_data(slug | slugs, metric, DateTime.t(), DateTime.t(), opts) ::
          aggregated_metric_timeseries_data_result()
  def aggregated_metric_timeseries_data(slug_or_slugs, metric, from, to, opts \\ [])

  def aggregated_metric_timeseries_data([], _, _, _, _), do: {:ok, %{}}

  def aggregated_metric_timeseries_data(slugs, metric, from, to, opts)
      when is_list(slugs) and length(slugs) > 1000 do
    # Break here otherwise the Enum.filter/2 will remove all errors and report a wrong result
    with {:ok, _source} <- opts_to_source(opts) do
      result =
        Enum.chunk_every(slugs, 1000)
        |> Sanbase.Parallel.map(
          &aggregated_metric_timeseries_data(&1, metric, from, to, opts),
          timeout: 55_000,
          max_concurrency: 8,
          ordered: false
        )
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(&elem(&1, 1))
        |> Enum.reduce(%{}, &Map.merge(&1, &2))

      {:ok, result}
    end
  end

  def aggregated_metric_timeseries_data(slug_or_slugs, metric, from, to, opts)
      when metric in @metrics and (is_binary(slug_or_slugs) or is_list(slug_or_slugs)) do
    with {:ok, source} <- opts_to_source(opts) do
      aggregation = Keyword.get(opts, :aggregation) || :avg
      slugs = List.wrap(slug_or_slugs)

      query_struct =
        aggregated_metric_timeseries_data_query(slugs, metric, from, to, source, aggregation)

      ClickhouseRepo.query_reduce(query_struct, %{}, fn
        [slug, value, has_changed], acc ->
          value = if has_changed == 1, do: value
          Map.put(acc, slug, value)
      end)
    end
  end

  @doc ~s"""
  Return the aggregated marketcap in USD and volume in USD for all slugs in the
  given interval.

  The default aggregation can be overriden by passing the :volume_aggregation
  and/or :marketcap_aggregation keys in the keyword options list
  The supported aggregations are: #{inspect(@aggregations)}
  """
  @spec aggregated_marketcap_and_volume(slug | slugs, DateTime.t(), DateTime.t(), opts) ::
          aggregated_marketcap_and_volume_result()
  def aggregated_marketcap_and_volume(slug_or_slugs, from, to, opts \\ [])

  def aggregated_marketcap_and_volume([], _, _, _), do: {:ok, %{}}

  def aggregated_marketcap_and_volume(slug_or_slugs, from, to, opts)
      when is_binary(slug_or_slugs) or is_list(slug_or_slugs) do
    with {:ok, source} <- opts_to_source(opts) do
      slugs = List.wrap(slug_or_slugs)

      query_struct = aggregated_marketcap_and_volume_query(slugs, from, to, source, opts)

      ClickhouseRepo.query_transform(query_struct, fn
        [slug, marketcap_usd, volume_usd, has_changed] ->
          %{
            slug: slug,
            marketcap_usd: marketcap_usd,
            marketcap: marketcap_usd,
            volume_usd: volume_usd,
            volume: volume_usd,
            has_changed: has_changed
          }
      end)
      |> maybe_add_percent_of_total_marketcap()
      |> maybe_nullify_values()
    end
  end

  def latest_prices_per_slug([], _, _) do
    {:ok, %{}}
  end

  def latest_prices_per_slug(slugs, source, limit_per_slug) when is_list(slugs) do
    query_struct = latest_prices_per_slug_query(slugs, source, limit_per_slug)

    ClickhouseRepo.query_reduce(query_struct, %{}, fn [slug, prices_usd, prices_btc], acc ->
      acc
      |> Map.put({slug, "USD"}, prices_usd)
      |> Map.put({slug, "BTC"}, prices_btc)
    end)
  end

  def slugs_by_filter(metric, from, to, operator, threshold, opts) do
    with {:ok, source} <- opts_to_source(opts) do
      aggregation = Keyword.get(opts, :aggregation) || :last

      query_struct =
        slugs_by_filter_query(metric, from, to, operator, threshold, aggregation, source)

      ClickhouseRepo.query_transform(query_struct, fn [slug, _value] -> slug end)
    end
  end

  def slugs_order(metric, from, to, direction, opts) do
    with {:ok, source} <- opts_to_source(opts) do
      aggregation = Keyword.get(opts, :aggregation) || :last

      query_struct = slugs_order_query(metric, from, to, direction, aggregation, source)

      ClickhouseRepo.query_transform(query_struct, fn [slug, _value] -> slug end)
    end
  end

  @doc ~s"""
  Return the last record  before the given `datetime`
  """
  @spec last_record_before(slug, DateTime.t(), opts) ::
          last_record_before_result()
  def last_record_before(slug, datetime, opts \\ [])

  def last_record_before(slug, datetime, opts) do
    with {:ok, source} <- opts_to_source(opts) do
      query_struct = last_record_before_query(slug, datetime, source)

      ClickhouseRepo.query_transform(
        query_struct,
        fn [price_usd, price_btc, marketcap_usd, volume_usd] ->
          %{
            price_usd: price_usd,
            price_btc: price_btc,
            marketcap_usd: marketcap_usd,
            marketcap: marketcap_usd,
            volume_usd: volume_usd,
            volume: volume_usd
          }
        end
      )
      |> maybe_unwrap_ok_value()
    end
  end

  @doc ~s"""
  Return open-high-close-low price data in USD for the provided slug
  in the given interval.
  """
  @spec ohlc(slug, DateTime.t(), DateTime.t(), opts) :: ohlc_result()
  def ohlc(slug, from, to, opts \\ []) do
    with {:ok, source} <- opts_to_source(opts) do
      query_struct = ohlc_query(slug, from, to, source)

      ClickhouseRepo.query_transform(query_struct, fn [open, high, low, close, has_changed] ->
        %{
          open_price_usd: open,
          high_price_usd: high,
          close_price_usd: close,
          low_price_usd: low,
          has_changed: has_changed
        }
      end)
      |> maybe_nullify_values()
      |> maybe_unwrap_ok_value()
    end
  end

  @doc ~s"""
  Return open-high-close-low price data in USD for the provided slug
  in the given interval.
  """
  @spec timeseries_ohlc_data(slug, DateTime.t(), DateTime.t(), interval, opts) ::
          timeseries_ohlc_data_result()
  def timeseries_ohlc_data(slug, from, to, interval, opts \\ []) do
    with {:ok, source} <- opts_to_source(opts) do
      query_struct = timeseries_ohlc_data_query(slug, from, to, interval, source)

      ClickhouseRepo.query_transform(
        query_struct,
        fn [timestamp, open, high, low, close] ->
          %{
            datetime: DateTime.from_unix!(timestamp),
            open_price_usd: open,
            high_price_usd: high,
            close_price_usd: close,
            low_price_usd: low
          }
        end
      )
    end
  end

  @doc ~s"""
  Return the sum of all marketcaps and volums of the slugs in the given interval
  """
  @spec combined_marketcap_and_volume(slugs, DateTime.t(), DateTime.t(), interval, opts) ::
          combined_marketcap_and_volume_result()
  def combined_marketcap_and_volume(slugs, from, to, interval, opts \\ [])
  def combined_marketcap_and_volume([], _, _, _, _), do: {:ok, []}

  def combined_marketcap_and_volume(slugs, from, to, interval, opts) when length(slugs) > 30 do
    # Break here otherwise the Enum.filter/2 will remove all errors and report a wrong result
    with {:ok, _source} <- opts_to_source(opts) do
      slugs
      |> Enum.chunk_every(30)
      |> Sanbase.Parallel.map(
        fn slugs_chunk ->
          cache_key = Enum.sort(slugs_chunk) |> Sanbase.Cache.hash()

          Sanbase.Cache.get_or_store({__MODULE__, __ENV__.function, cache_key}, fn ->
            combined_marketcap_and_volume(slugs_chunk, from, to, interval, opts)
          end)
        end,
        max_concurrency: 8
      )
      |> Enum.filter(&match?({:ok, _}, &1))
      |> combine_marketcap_and_volume_results()
    end
  end

  def combined_marketcap_and_volume(slug_or_slugs, from, to, interval, opts) do
    with {:ok, source} <- opts_to_source(opts) do
      slugs = List.wrap(slug_or_slugs)

      query_struct = combined_marketcap_and_volume_query(slugs, from, to, interval, source)

      ClickhouseRepo.query_transform(
        query_struct,
        fn [timestamp, marketcap_usd, volume_usd, has_changed] ->
          %{
            datetime: DateTime.from_unix!(timestamp),
            marketcap_usd: marketcap_usd,
            marketcap: marketcap_usd,
            volume_usd: volume_usd,
            volume: volume_usd,
            has_changed: has_changed
          }
        end
      )
      |> remove_missing_values()
    end
    |> maybe_add_percent_of_total_marketcap()
  end

  def available_slugs(opts \\ [])

  def available_slugs(opts) do
    with {:ok, source} <- opts_to_source(opts) do
      slugs =
        Sanbase.Project.List.projects_with_source(source)
        |> Enum.map(& &1.slug)

      {:ok, slugs}
    end
  end

  def slugs_with_volume_over(volume, opts \\ [])

  def slugs_with_volume_over(volume, opts) when is_number(volume) do
    with {:ok, source} <- opts_to_source(opts) do
      query_struct = slugs_with_volume_over_query(volume, source)

      ClickhouseRepo.query_transform(query_struct, fn [slug] -> slug end)
    end
  end

  def has_data?(slug) do
    query_struct = select_any_record_query(slug)

    case ClickhouseRepo.query_transform(query_struct, & &1) do
      {:ok, [_]} -> {:ok, true}
      {:ok, []} -> {:ok, false}
      {:error, error} -> {:error, error}
    end
  end

  @doc ~s"""
  Return the first datetime for which `slug` has data
  """
  @spec first_datetime(slug, opts) :: {:ok, DateTime.t()} | {:ok, nil} | {:error, error}
  def first_datetime(slug, opts \\ [])

  def first_datetime("TOTAL_ERC20", _), do: ~U[2015-07-30 00:00:00Z]

  def first_datetime(slug, opts) do
    with {:ok, source} <- opts_to_source(opts) do
      query_struct = first_datetime_query(slug, source)

      ClickhouseRepo.query_transform(query_struct, fn
        [timestamp] -> DateTime.from_unix!(timestamp)
      end)
      |> maybe_unwrap_ok_value()
    end
  end

  def last_datetime_computed_at(slug) do
    query_struct = last_datetime_computed_at_query(slug)

    ClickhouseRepo.query_transform(query_struct, fn [datetime] ->
      DateTime.from_unix!(datetime)
    end)
    |> maybe_unwrap_ok_value()
  end

  # Private functions

  # Combine 2 price points. If `left` is empty then this is a new/initial price point
  defp combine_price_points(left, right) do
    %{
      marketcap: (left[:marketcap] || 0) + (right[:marketcap] || 0),
      marketcap_usd: (left[:marketcap_usd] || 0) + (right[:marketcap_usd] || 0),
      volume: (left[:volume] || 0) + (right[:volume] || 0),
      volume_usd: (left[:volume_usd] || 0) + (right[:volume_usd] || 0)
    }
  end

  defp update_price_point_in_map(map, price_point) do
    %{datetime: datetime} = price_point

    initial = combine_price_points(%{}, price_point)

    Map.update(map, datetime, initial, fn
      %{has_changed: 0} = elem -> elem
      elem -> combine_price_points(elem, price_point)
    end)
  end

  defp combine_marketcap_and_volume_results(results) do
    results
    |> Enum.reduce(%{}, fn {:ok, data}, acc ->
      Enum.reduce(data, acc, &update_price_point_in_map(&2, &1))
    end)
    |> Enum.map(fn {datetime, data} -> Map.put(data, :datetime, datetime) end)
    |> Enum.sort_by(& &1.datetime, {:asc, DateTime})
    |> wrap_ok()
  end

  defp maybe_add_percent_of_total_marketcap({:ok, data}) do
    total_marketcap_usd =
      Enum.reduce(data, 0, fn elem, acc -> acc + (elem.marketcap_usd || 0) end)

    result =
      Enum.map(
        data,
        fn %{marketcap_usd: marketcap_usd} = elem ->
          marketcap_percent =
            Sanbase.Math.percent_of(marketcap_usd, total_marketcap_usd,
              type: :between_0_and_1,
              precision: 5
            )

          Map.put(elem, :marketcap_percent, marketcap_percent)
        end
      )

    {:ok, result}
  end

  defp maybe_add_percent_of_total_marketcap({:error, error}), do: {:error, error}

  defp opts_to_source(opts) do
    case Keyword.get(opts, :source, @default_source) do
      source when source in @supported_sources ->
        {:ok, source}

      source when source in @deprecated_sources ->
        {:error,
         "Price related data source #{inspect(source)} is deprecated. Supported price related sources are: #{@supported_sources_str}"}

      source ->
        {:error,
         "Price related data source #{inspect(source)} is not supported. Supported price related sources are: #{@supported_sources_str}"}
    end
  end
end
