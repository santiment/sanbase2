defmodule Sanbase.ExternalServices.Coinmarketcap.PricePoint do
  require Logger

  @marketcap_usd_limit 10_000_000_000_000
  @volume_usd_limit 500_000_000_000
  @price_usd_limit 1_000_000
  @price_btc_limit 1_000

  @prices_source "coinmarketcap"
  defstruct [
    :ticker,
    :slug,
    :datetime,
    :marketcap_usd,
    :volume_usd,
    :price_usd,
    :price_btc
  ]

  def json_kv_tuple(%__MODULE__{datetime: datetime} = point, slug, source \\ @prices_source) do
    key = source <> "_" <> slug <> "_" <> DateTime.to_iso8601(datetime)

    value =
      %{
        timestamp: DateTime.to_unix(datetime),
        source: source,
        slug: slug
      }
      |> Map.merge(price_point_fields(point))
      |> Jason.encode!()

    {key, value}
  end

  defguard num_ge(num, threshold)
           when is_number(num) and is_number(threshold) and num >= threshold

  defguard num_le(num, threshold)
           when is_number(num) and is_number(threshold) and num <= threshold

  def sanity_filters([]), do: []

  def sanity_filters([%__MODULE__{} | _] = price_points) when is_list(price_points) do
    # For each price point nullify the fields that exceed the limits
    Enum.map(price_points, fn %__MODULE__{} = price_point ->
      map =
        price_point
        |> Map.from_struct()
        |> Map.new(fn
          {:volume_usd, value} when num_ge(value, @volume_usd_limit) ->
            Logger.info("PricePoint sanitizing #{price_point.slug} Volume USD: #{value}")

            {:volume_usd, nil}

          {:price_usd, value} when num_ge(value, @price_usd_limit) ->
            Logger.info("PricePoint sanitizing #{price_point.slug} Price USD: #{value}")

            {:price_usd, nil}

          {:price_btc, value} when num_ge(value, @price_btc_limit) ->
            Logger.info("PricePoint sanitizing #{price_point.slug} Price BTC: #{value}")
            {:price_btc, nil}

          {:marketcap_usd, value}
          when num_ge(value, @marketcap_usd_limit) or num_le(value, 0) ->
            Logger.info("PricePoint sanitizing #{price_point.slug} Marketcap USD: #{value}")
            {:marketcap_usd, nil}

          {k, v} ->
            {k, v}
        end)

      struct!(__MODULE__, map)
    end)
  end

  def sanity_filters(%__MODULE__{} = price_point) do
    [price_point]
    |> sanity_filters()
    |> hd()
  end

  # Private functions

  defp price_point_fields(%__MODULE__{
         marketcap_usd: marketcap_usd,
         volume_usd: volume_usd,
         price_btc: price_btc,
         price_usd: price_usd
       }) do
    %{
      price_usd: price_usd,
      price_btc: price_btc,
      volume_usd: volume_usd,
      marketcap_usd: marketcap_usd
    }
  end
end
