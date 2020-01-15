defmodule Sanbase.Price do
  use Ecto.Schema

  import Sanbase.Price.SqlQuery

  alias Sanbase.Model.Project

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @default_source "coinmarketcap"
  @metrics [:price_usd, :price_btc, :marketcap_usd, :volume_usd]
  @aggregations aggregations()
  @type metric :: :price_usd | :price_btc | :marketcap_usd | :volume_usd

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

  @table "asset_prices"
  schema @table do
    field(:datetime, :naive_datetime, source: :dt)
    field(:source, :string)
    field(:slug, :string)
    field(:price_usd, :float)
    field(:price_btc, :float)
    field(:marketcap_usd, :float)
    field(:volume_usd, :float)
  end

  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _), do: raise("Cannot change the asset_prices table")

  @doc ~s"""
  Return timeseries data for the given time period where every point consists
  of price in USD, price in BTC, marketcap in USD and volume in USD
  """
  @spec timeseries_data(slug, DateTime.t(), DateTime.t(), interval, opts) ::
          timeseries_data_result
  def timeseries_data(slug, from, to, interval, opts \\ [])

  def timeseries_data("TOTAL_ERC20", from, to, interval, opts) do
    Project.List.erc20_projects_slugs()
    |> combined_marketcap_and_volume(from, to, interval, opts)
  end

  def timeseries_data(slug, from, to, interval, opts) when is_binary(slug) do
    source = Keyword.get(opts, :source, @default_source)
    {query, args} = timeseries_data_query(slug, from, to, interval, source)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn
        [timestamp, price_usd, price_btc, marketcap_usd, volume_usd, has_changed] ->
          %{
            datetime: DateTime.from_unix!(timestamp),
            price_usd: price_usd,
            price_btc: price_btc,
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
    source = Keyword.get(opts, :source, @default_source)
    slugs = List.wrap(slug_or_slugs)

    {query, args} = aggregated_timeseries_data_query(slugs, from, to, source)

    ClickhouseRepo.query_transform(query, args, fn
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

  def aggregated_metric_timeseries_data(slug_or_slugs, metric, from, to, opts)
      when metric in @metrics and (is_binary(slug_or_slugs) or is_list(slug_or_slugs)) do
    source = Keyword.get(opts, :source, @default_source)
    slugs = List.wrap(slug_or_slugs)

    {query, args} = aggregated_metric_timeseries_data_query(slugs, metric, from, to, source, opts)

    ClickhouseRepo.query_reduce(query, args, %{}, fn
      [slug, value, has_changed], acc ->
        value = if has_changed == 1, do: value
        Map.put(acc, slug, value)
    end)
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
    source = Keyword.get(opts, :source, @default_source)
    slugs = List.wrap(slug_or_slugs)

    {query, args} = aggregated_marketcap_and_volume_query(slugs, from, to, source, opts)

    ClickhouseRepo.query_transform(query, args, fn
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

  @doc ~s"""
  Return the last record  before the given `datetime`
  """
  @spec last_record_before(slug, DateTime.t(), opts) ::
          last_record_before_result()
  def last_record_before(slug, datetime, opts \\ [])

  def last_record_before(slug, datetime, opts) do
    source = Keyword.get(opts, :source, @default_source)
    {query, args} = last_record_before_query(slug, datetime, source)

    ClickhouseRepo.query_transform(
      query,
      args,
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

  @doc ~s"""
  Return open-high-close-low price data in USD for the provided slug
  in the given interval.
  """
  @spec ohlc(slug, DateTime.t(), DateTime.t(), opts) :: ohlc_result()
  def ohlc(slug, from, to, opts \\ []) do
    source = Keyword.get(opts, :source, @default_source)
    {query, args} = ohlc_query(slug, from, to, source)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn
        [open, high, low, close, has_changed] ->
          %{
            open_price_usd: open,
            high_price_usd: high,
            close_price_usd: close,
            low_price_usd: low,
            has_changed: has_changed
          }
      end
    )
    |> maybe_nullify_values()
    |> maybe_unwrap_ok_value()
  end

  @doc ~s"""
  Return open-high-close-low price data in USD for the provided slug
  in the given interval.
  """
  @spec timeseries_ohlc_data(slug, DateTime.t(), DateTime.t(), interval, opts) ::
          timeseries_ohlc_data_result()
  def timeseries_ohlc_data(slug, from, to, interval, opts \\ []) do
    source = Keyword.get(opts, :source, @default_source)
    {query, args} = timeseries_ohlc_data_query(slug, from, to, interval, source)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn
        [timestamp, open, high, low, close, has_changed] ->
          %{
            datetime: DateTime.from_unix!(timestamp),
            open_price_usd: open,
            high_price_usd: high,
            close_price_usd: close,
            low_price_usd: low,
            has_changed: has_changed
          }
      end
    )
    |> remove_missing_values()
  end

  @doc ~s"""
  Return the sum of all marketcaps and volums of the slugs in the given interval
  """
  @spec combined_marketcap_and_volume(slugs, DateTime.t(), DateTime.t(), interval, opts) ::
          combined_marketcap_and_volume_result()
  def combined_marketcap_and_volume(slugs, from, to, interval, opts \\ [])
  def combined_marketcap_and_volume([], _, _, _, _), do: {:ok, []}

  def combined_marketcap_and_volume(slugs, from, to, interval, opts) when length(slugs) > 30 do
    slugs
    |> Enum.chunk_every(30)
    |> Sanbase.Parallel.map(
      fn slugs_chunk ->
        cache_key = Enum.sort(slugs_chunk) |> :erlang.phash2()

        Sanbase.Cache.get_or_store({__MODULE__, __ENV__.function, cache_key}, fn ->
          combined_marketcap_and_volume(slugs_chunk, from, to, interval, opts)
        end)
      end,
      max_concurrency: 8
    )
    |> Enum.filter(&match?({:ok, _}, &1))
    |> combine_marketcap_and_volume_results()
  end

  def combined_marketcap_and_volume(slug_or_slugs, from, to, interval, opts) do
    slugs = List.wrap(slug_or_slugs)
    source = Keyword.get(opts, :source, @default_source)

    {query, args} = combined_marketcap_and_volume_query(slugs, from, to, interval, source)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn
        [timestamp, marketcap_usd, volume_usd, has_changed] ->
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
    |> maybe_add_percent_of_total_marketcap()
  end

  def slugs_with_volume_over(volume, opts \\ [])

  def slugs_with_volume_over(volume, opts) when is_number(volume) do
    source = Keyword.get(opts, :source, @default_source)
    {query, args} = slugs_with_volume_over_query(volume, source)

    ClickhouseRepo.query_transform(query, args, fn [slug] -> slug end)
  end

  @doc ~s"""
  Return the first datetime for which `slug` has data
  """
  @spec first_datetime(slug, opts) :: {:ok, DateTime.t()} | {:error, error}
  def first_datetime(slug, opts \\ [])

  def first_datetime("TOTAL_ERC20", _), do: ~U[2015-07-30 00:00:00Z]

  def first_datetime(slug, opts) do
    source = Keyword.get(opts, :source, @default_source)
    {query, args} = first_datetime_query(slug, source)

    ClickhouseRepo.query_transform(query, args, fn [timestamp] ->
      DateTime.from_unix!(timestamp)
    end)
    |> maybe_unwrap_ok_value()
  end

  # Private functions

  defp combine_marketcap_and_volume_results(results) do
    result =
      results
      |> Enum.map(fn {:ok, data} -> data end)
      |> Enum.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(fn list ->
        case Enum.any?(list, &(&1.has_changed != 0)) do
          true ->
            %{datetime: datetime} = List.last(list)

            data =
              Enum.reduce(
                list,
                %{volume: 0, volume_usd: 0, marketcap: 0, marketcap_usd: 0},
                fn elem, acc ->
                  %{
                    marketcap: acc.marketcap + (elem.marketcap || 0),
                    marketcap_usd: acc.marketcap_usd + (elem.marketcap_usd || 0),
                    volume: acc.volume + (elem.volume || 0),
                    volume_usd: acc.volume_usd + (elem.volume_usd || 0)
                  }
                end
              )

            Map.put(data, :datetime, datetime)

          false ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, result}
  end

  # Take a list of maps and rewrite them if necessary.
  # All values of keys different than :slug and :datetime are set to nil
  # if :has_changed equals zero
  defp maybe_nullify_values({:ok, data}) do
    result =
      Enum.map(
        data,
        fn
          %{has_changed: 0} = elem ->
            # use :maps.map/2 instead of Enum.map/2 to avoid unnecessary Map.new/1
            :maps.map(
              fn
                key, value when key in [:slug, :datetime] -> value
                _, _ -> nil
              end,
              Map.delete(elem, :has_changed)
            )

          elem ->
            Map.delete(elem, :has_changed)
        end
      )

    {:ok, result}
  end

  defp maybe_nullify_values({:error, error}), do: {:error, error}

  defp remove_missing_values({:ok, data}) do
    {:ok, Enum.reject(data, &(&1.has_changed == 0))}
  end

  defp remove_missing_values({:error, error}), do: {:error, error}

  defp maybe_unwrap_ok_value({:ok, [value]}), do: {:ok, value}
  defp maybe_unwrap_ok_value(data), do: data

  defp maybe_add_percent_of_total_marketcap({:ok, data}) do
    total_marketcap_usd =
      Enum.reduce(data, 0, fn elem, acc -> acc + (elem.marketcap_usd || 0) end)

    result =
      Enum.map(
        data,
        fn %{marketcap_usd: marketcap_usd} = elem ->
          marketcap_percent =
            Sanbase.Math.percent_of(marketcap_usd, total_marketcap_usd, type: :between_0_and_1)
            |> Float.floor(5)

          Map.put(elem, :marketcap_percent, marketcap_percent)
        end
      )

    {:ok, result}
  end

  defp maybe_add_percent_of_total_marketcap({:error, error}), do: {:error, error}
end
