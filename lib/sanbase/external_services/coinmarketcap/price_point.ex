defmodule Sanbase.ExternalServices.Coinmarketcap.PricePoint do
  require Logger

  @custom_marketcap_usd_limit_map %{
    "TOTAL_MARKET" => 20_000_000_000_000,
    "bitcoin" => 10_000_000_000_000,
    "ethereum" => 2_000_000_000_000,
    "tether" => 2_000_000_000_000,
    "xrp" => 2_000_000_000_000,
    "solana" => 2_000_000_000_000,
    "bnb" => 2_000_000_000_000
  }

  @custom_volume_usd_limit_map %{
    "TOTAL_MARKET" => 3_000_000_000_000,
    "tether" => 1_000_000_000_000,
    "bitcoin" => 1_000_000_000_000,
    "ethereum" => 1_000_000_000_000,
    "dai" => 500_000_000_000
  }

  @marketcap_usd_limit 300_000_000_000
  @volume_usd_limit 200_000_000_000
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

  defguard num_gte(num, threshold)
           when is_number(num) and is_number(threshold) and num >= threshold

  defguard num_lt(num, threshold)
           when is_number(num) and is_number(threshold) and num < threshold

  def sanity_filters([], _slug), do: []

  def sanity_filters([%__MODULE__{} | _] = price_points, slug) when is_list(price_points) do
    # For each price point nullify the fields that exceed the limits
    Enum.map(price_points, fn %__MODULE__{} = price_point ->
      # For volume and marketcap we use a little bit higher limits for some known big assets
      # and smaller limits for the rest. Before we had too big default limit, which was
      # allowing some very big marketcaps like 10T
      marketcap_limit = Map.get(@custom_marketcap_usd_limit_map, slug, @marketcap_usd_limit)
      volume_limit = Map.get(@custom_volume_usd_limit_map, slug, @volume_usd_limit)

      map =
        price_point
        |> Map.from_struct()
        |> Map.new(fn
          {:marketcap_usd, value}
          when num_gte(value, marketcap_limit) or num_lt(value, 0) ->
            Logger.info("PricePoint sanitizing #{slug} Marketcap USD: #{value}")
            {:marketcap_usd, nil}

          {:volume_usd, value}
          when num_gte(value, volume_limit) ->
            Logger.info("PricePoint sanitizing #{slug} Volume USD: #{value}")

            {:volume_usd, nil}

          {:price_usd, value} when num_gte(value, @price_usd_limit) ->
            Logger.info("PricePoint sanitizing #{slug} Price USD: #{value}")

            {:price_usd, nil}

          {:price_btc, value} when num_gte(value, @price_btc_limit) ->
            Logger.info("PricePoint sanitizing #{slug} Price BTC: #{value}")
            {:price_btc, nil}

          {k, v} ->
            {k, v}
        end)

      struct!(__MODULE__, map)
    end)
  end

  def sanity_filters(%__MODULE__{} = price_point, slug) do
    [price_point]
    |> sanity_filters(slug)
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
