defmodule SanbaseWeb.Graphql.InfluxdbDataloader do
  alias Sanbase.Prices
  alias SanbaseWeb.Graphql.Cache
  alias SanbaseWeb.Graphql.Helpers.Utils

  require Logger

  @max_concurrency 30

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(:volume_change_24h, args) do
    measurements =
      args |> Enum.map(&Sanbase.Influxdb.Measurement.name_from/1) |> Enum.reject(&is_nil/1)

    now = Timex.now()
    yesterday = Timex.shift(now, days: -1)
    two_days_ago = Timex.shift(now, days: -2)

    measurements
    |> Enum.chunk_every(50)
    |> Sanbase.Parallel.map(
      fn
        [_ | _] = measurements ->
          with {:ok, volumes_last_24h} <-
                 Prices.Store.fetch_average_volume(measurements, yesterday, now),
               {:ok, volumes_previous_24h} <-
                 Prices.Store.fetch_average_volume(measurements, two_days_ago, yesterday) do
            calculate_volume_percent_change_24h(volumes_previous_24h, volumes_last_24h)
          else
            error ->
              Logger.warn(
                "Cannot fetch average volume for a list of projects #{inspect(measurements)}. Reason: #{
                  inspect(error)
                }"
              )

              []
          end
          |> Enum.reject(&is_nil/1)

        [] ->
          []
      end,
      max_concurrency: 8,
      ordered: false,
      map_type: :flat_map
    )
    |> Map.new()
  end

  def query({:price, measurement}, ids) do
    ids
    |> Enum.uniq()
    |> Sanbase.Parallel.map(
      fn id ->
        {id, fetch_price(measurement, id)}
      end,
      max_concurrency: @max_concurrency,
      ordered: false
    )
    |> Map.new()
  end

  # Helper functions

  defp calculate_volume_percent_change_24h(volumes_previous_24h, volumes_last_24h) do
    volumes_previous_24h_map = volumes_previous_24h |> Map.new()

    volumes_last_24h
    |> Enum.map(fn {name, today_vol} ->
      yesterday_vol = Map.get(volumes_previous_24h_map, name, 0)

      if yesterday_vol > 1 do
        {name, Sanbase.Math.percent_change(yesterday_vol, today_vol)}
      end
    end)
  end

  # TODO: not covered in tests
  defp fetch_price(measurement, :last) do
    Cache.wrap(
      fn -> fetch_last_price_record(measurement) end,
      :fetch_price_last_record,
      %{measurement: measurement}
    ).()
  end

  defp fetch_price(measurement, %{from: from, to: to, interval: interval} = args) do
    {:ok, from, to, interval} =
      Utils.calibrate_interval(Prices.Store, measurement, from, to, interval, 60)

    Cache.wrap(
      fn ->
        Prices.Store.fetch_prices_with_resolution(measurement, from, to, interval)
      end,
      :fetch_prices_with_resolution,
      Map.merge(%{measurement: measurement}, args)
    ).()
  end

  defp fetch_last_price_record(measurement) do
    case Prices.Store.last_record(measurement) do
      {:ok, [[_dt, _mcap, price_btc, price_usd, _volume]]} ->
        {price_usd, price_btc}

      _error ->
        {nil, nil}
    end
  end
end
