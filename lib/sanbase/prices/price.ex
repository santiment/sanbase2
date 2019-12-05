defmodule Sanbase.Price do
  use Ecto.Schema

  import Sanbase.Price.SqlQuery

  alias Sanbase.Model.Project

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @metrics [:price_usd, :price_btc, :marketcap_usd, :volume_usd]
  @type metric :: :price_usd | :price_btc | :marketcap_usd | :volume_usd

  @type slug :: String.t()
  @type slugs :: list(slug)
  @type interval :: String.t()

  @type aggregated_metric_timeseries_data_map :: %{
          :slug => String.t(),
          :value => float()
        }

  @type aggregated_metric_timeseries_data_result ::
          {:ok, aggregated_metric_timeseries_data_map()} | {:error, String.t()}

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

  def changeest(_, _), do: raise("Cannot change the asset_prices table")

  def timeseries_data(slug, from, to, interval, opts \\ [])

  def timeseries_data("TOTAL_ERC20", from, to, interval, opts) do
    erc20_project_slugs = Project.List.erc20_projects_slugs()
  end

  def timeseries_data(slug, from, to, interval, opts) when is_binary(slug) do
    source = Keyword.get(opts, :source, "coinmarketcap")
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
            volume_usd: volume_usd,
            has_changed: has_changed
          }
      end
    )
    |> maybe_nullify_values()
  end

  def aggregated_timeseries_data(slug_or_slugs, from, to, opts \\ [])

  def aggregated_timeseries_data([], _, _, _), do: {:ok, []}

  def aggregated_timeseries_data(slug_or_slugs, from, to, opts)
      when is_binary(slug_or_slugs) or is_list(slug_or_slugs) do
    source = Keyword.get(opts, :source, "coinmarketcap")
    slugs = List.wrap(slug_or_slugs)

    {query, args} = aggregated_timeseries_data_query(slugs, from, to, source)

    ClickhouseRepo.query_transform(query, args, fn
      [slug, price_usd, price_btc, marketcap_usd, volume_usd, has_changed] ->
        %{
          slug: slug,
          price_usd: price_usd,
          price_btc: price_btc,
          marketcap_usd: marketcap_usd,
          volume_usd: volume_usd,
          has_changed: has_changed
        }
    end)
    |> maybe_nullify_values()
  end

  @doc ~s"""
  Return the aggregated data for all slugs for the provided metric in
  the given interval
  The default aggregation can be overriden by passing the :aggregation
  key with as part of the keyword options list. The supported aggregations are:
  :any, :sum, :avg, :min, :max, :last, :first, :median

  In the success case the result is a map where the slug is the key and the value
  is the aggregated metric's value
  """
  @spec aggregated_metric_timeseries_data(
          slug | slugs,
          metric,
          DateTime.t(),
          DateTime.t(),
          Keyword.t()
        ) :: aggregated_metric_timeseries_data_result()
  def aggregated_metric_timeseries_data(slug_or_slugs, metric, from, to, opts \\ [])

  def aggregated_metric_timeseries_data([], _, _, _, _), do: {:ok, %{}}

  def aggregated_metric_timeseries_data(slug_or_slugs, metric, from, to, opts)
      when metric in @metrics and (is_binary(slug_or_slugs) or is_list(slug_or_slugs)) do
    source = Keyword.get(opts, :source, "coinmarketcap")
    slugs = List.wrap(slug_or_slugs)

    {query, args} = aggregated_metric_timeseries_data_query(slugs, metric, from, to, source)

    ClickhouseRepo.query_reduce(query, args, %{}, fn
      [slug, value, has_changed], acc ->
        value = if has_changed == 1, do: value
        Map.put(acc, slug, value)
    end)
  end

  def ohlc(slug, from, to, interval, opts \\ []) do
    source = Keyword.get(opts, :source, "coinmarketcap")
    {query, args} = ohlc_query(slug, from, to, interval, source)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn
        [timestamp, open, high, low, close, has_changed] ->
          %{
            datetime: DateTime.from_unix!(timestamp),
            open: open,
            high: high,
            close: close,
            low: low,
            has_changed: has_changed
          }
      end
    )
    |> maybe_nullify_values()
  end

  # Take a list of maps and rewrite them if necessary.
  # All values of keys different than :slug and :datetime are set to nil
  # if :has_changed equals zero
  defp maybe_nullify_values({:ok, data}) do
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
  end

  defp maybe_nullify_values({:error, error}), do: {:error, error}
end
